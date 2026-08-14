#include "gamepad_bridge.h"

#include <hidsdi.h>
#include <hidpi.h>

#include <algorithm>
#include <cmath>

// XInput state is needed without pulling in the XInput.h header (which drags
// in the whole Windows SDK headers). The layout is stable:
//
//   uint32_t dwPacketNumber;
//   uint16_t wButtons;
//   uint8_t  bLeftTrigger;
//   uint8_t  bRightTrigger;
//   int16_t  sThumbLX;
//   int16_t  sThumbLY;
//   int16_t  sThumbRX;
//   int16_t  sThumbRY;

constexpr int kMaxControllers = 4;

// wButtons flags (XINPUT_GAMEPAD_*).
constexpr uint16_t kDpadUp = 0x0001;
constexpr uint16_t kDpadDown = 0x0002;
constexpr uint16_t kDpadLeft = 0x0004;
constexpr uint16_t kDpadRight = 0x0008;
constexpr uint16_t kStart = 0x0010;
constexpr uint16_t kBack = 0x0020;
constexpr uint16_t kLeftThumb = 0x0040;
constexpr uint16_t kRightThumb = 0x0080;
constexpr uint16_t kLeftShoulder = 0x0100;
constexpr uint16_t kRightShoulder = 0x0200;
constexpr uint16_t kButtonA = 0x1000;
constexpr uint16_t kButtonB = 0x2000;
constexpr uint16_t kButtonX = 0x4000;
constexpr uint16_t kButtonY = 0x8000;

constexpr DWORD kErrorSuccess = 0;
constexpr DWORD kErrorDeviceNotConnected = 0x48F;

// HID usage page / usages that identify a joystick or gamepad.
constexpr USHORT kUsagePageGenericDesktop = 0x0001;
constexpr USHORT kUsageJoystick = 0x0004;
constexpr USHORT kUsageGamepad = 0x0005;

// ---------------------------------------------------------------------------
// Minimal XINPUT structures (match the documented layout).
// ---------------------------------------------------------------------------
struct XinputGamepad {
  uint16_t wButtons;
  uint8_t bLeftTrigger;
  uint8_t bRightTrigger;
  int16_t sThumbLX;
  int16_t sThumbLY;
  int16_t sThumbRX;
  int16_t sThumbRY;
};

struct XinputState {
  uint32_t dwPacketNumber;
  XinputGamepad Gamepad;
};

namespace {

constexpr UINT kGamepadUpdateMessage = WM_APP + 1;

void PostGamepadUpdate(HWND hwnd) {
  PostMessage(hwnd, kGamepadUpdateMessage, 0, 0);
}

double NormalizeStick(SHORT value) {
  constexpr double kRange = 32767.0;
  // Small dead zone (roughly +/-3%) keeps the rest position quiet.
  constexpr double kDeadZone = 0.03;
  double normalized = value / kRange;
  normalized = std::max(-1.0, std::min(1.0, normalized));
  if (std::fabs(normalized) < kDeadZone) return 0.0;
  return normalized;
}

double NormalizeTrigger(BYTE value) {
  return static_cast<double>(value) / 255.0;
}

// A ButtonCaps range expands to a list of usage ids.
void ExpandButtonCaps(const HIDP_BUTTON_CAPS& cap, std::vector<USHORT>& usages) {
  if (cap.IsRange) {
    for (USHORT u = cap.Range.UsageMin; u <= cap.Range.UsageMax; ++u) {
      usages.push_back(u);
    }
  } else {
    usages.push_back(cap.NotRange.Usage);
  }
}

}  // namespace

// ---------------------------------------------------------------------------
// GamepadBridge
// ---------------------------------------------------------------------------

GamepadBridge::GamepadBridge(flutter::BinaryMessenger* messenger, HWND hwnd)
    : hwnd_(hwnd) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.naji.najimessenger/gamepads",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        this->HandleMethodCall(call, std::move(result));
      });
}

GamepadBridge::~GamepadBridge() { Shutdown(); }

void GamepadBridge::Shutdown() {
  running_ = false;
  if (poll_thread_.joinable()) {
    poll_thread_.join();
  }
  UnloadXInput();
}

bool GamepadBridge::LoadXInput() {
  if (xinput_get_state_) return true;

  // Prefer the newest 1.4 then the older 1.3 / 1.1.
  static const wchar_t* kNames[] = {L"xinput1_4.dll", L"xinput1_3.dll",
                                    L"xinput1_1.dll"};
  for (const wchar_t* name : kNames) {
    HINSTANCE lib = LoadLibraryW(name);
    if (!lib) continue;
    auto fn = reinterpret_cast<XInputGetStateFn>(GetProcAddress(lib, "XInputGetState"));
    if (fn) {
      xinput_lib_ = lib;
      xinput_get_state_ = fn;
      return true;
    }
    FreeLibrary(lib);
  }
  return false;
}

void GamepadBridge::UnloadXInput() {
  xinput_get_state_ = nullptr;
  if (xinput_lib_) {
    FreeLibrary(xinput_lib_);
    xinput_lib_ = nullptr;
  }
}

std::string GamepadBridge::StateSnapshot::Signature() const {
  std::string sig;
  for (const auto& pad : pads) {
    if (!pad.connected) {
      sig += "-;";
      continue;
    }
    sig += "c," + std::to_string(pad.buttons) + ","
        + std::to_string(pad.left_trigger) + ","
        + std::to_string(pad.right_trigger) + ","
        + std::to_string(pad.thumb_lx) + ","
        + std::to_string(pad.thumb_ly) + ","
        + std::to_string(pad.thumb_rx) + ","
        + std::to_string(pad.thumb_ry) + ";";
  }
  return sig;
}

std::string GamepadBridge::RawPad::Signature() const {
  std::string sig;
  for (size_t i = 0; i < button_state.size(); ++i) {
    sig += std::to_string(static_cast<int>(button_state[i]));
  }
  sig += "|";
  for (size_t i = 0; i < axis_state.size(); ++i) {
    sig += std::to_string(static_cast<int>(axis_state[i] * 1000.0));
    sig += ",";
  }
  return sig;
}

GamepadBridge::StateSnapshot GamepadBridge::ReadSnapshot() const {
  StateSnapshot snapshot;
  if (!xinput_get_state_) return snapshot;

  for (DWORD index = 0; index < kMaxControllers; ++index) {
    XinputState state{};
    const DWORD result = xinput_get_state_(index, &state);
    if (result != kErrorSuccess && result != kErrorDeviceNotConnected) {
      continue;
    }
    if (result == kErrorDeviceNotConnected) {
      snapshot.pads[index].connected = false;
      continue;
    }
    PadSnapshot& pad = snapshot.pads[index];
    pad.connected = true;
    pad.packet = state.dwPacketNumber;
    pad.buttons = state.Gamepad.wButtons;
    pad.left_trigger = state.Gamepad.bLeftTrigger;
    pad.right_trigger = state.Gamepad.bRightTrigger;
    pad.thumb_lx = state.Gamepad.sThumbLX;
    pad.thumb_ly = state.Gamepad.sThumbLY;
    pad.thumb_rx = state.Gamepad.sThumbRX;
    pad.thumb_ry = state.Gamepad.sThumbRY;
    snapshot.any_connected = true;
  }
  return snapshot;
}

void GamepadBridge::RefreshRawDevices() {
  UINT device_count = 0;
  if (GetRawInputDeviceList(nullptr, &device_count, sizeof(RAWINPUTDEVICELIST)) != 0) {
    return;
  }
  if (device_count == 0) {
    std::lock_guard<std::mutex> lock(raw_mutex_);
    raw_pads_.clear();
    latest_raw_signature_.clear();
    return;
  }

  std::vector<RAWINPUTDEVICELIST> devices(device_count);
  const UINT got = GetRawInputDeviceList(devices.data(), &device_count,
                                         sizeof(RAWINPUTDEVICELIST));
  if (got == UINT_MAX) {
    return;
  }

  std::vector<RawPad> fresh;
  for (UINT i = 0; i < got; ++i) {
    const HANDLE handle = devices[i].hDevice;
    if (devices[i].dwType != RIM_TYPEHID) {
      continue;
    }

    // Read the device name (unique id).
    UINT name_size = 0;
    GetRawInputDeviceInfoW(handle, RIDI_DEVICENAME, nullptr, &name_size);
    std::wstring wname;
    if (name_size > 0) {
      std::vector<wchar_t> buf(name_size + 1);
      if (GetRawInputDeviceInfoW(handle, RIDI_DEVICENAME, buf.data(),
                                 &name_size) != UINT_MAX) {
        wname.assign(buf.data());
      }
    }

    // Preparsed data for HIDP parsing.
    UINT size = 0;
    GetRawInputDeviceInfo(handle, RIDI_PREPARSEDDATA, nullptr, &size);
    if (size == 0) {
      continue;
    }
    std::vector<BYTE> preparsed(size);
    if (GetRawInputDeviceInfo(handle, RIDI_PREPARSEDDATA, preparsed.data(),
                              &size) != size) {
      continue;
    }

    HIDP_CAPS caps{};
    if (HidP_GetCaps(reinterpret_cast<PHIDP_PREPARSED_DATA>(preparsed.data()),
                     &caps) != HIDP_STATUS_SUCCESS) {
      continue;
    }

    // Only consider joystick/gamepad class devices.
    if (caps.UsagePage != kUsagePageGenericDesktop ||
        (caps.Usage != kUsageJoystick && caps.Usage != kUsageGamepad)) {
      continue;
    }

    RawPad pad;
    pad.device = handle;
    std::string device_id;
    device_id.reserve(wname.size());
    for (wchar_t ch : wname) {
      device_id.push_back(static_cast<char>(ch));
    }
    // XInput controllers are enumerated as HID devices too; the driver tags
    // them with "IG_" in the device instance id. Skip them so they are only
    // reported once (through the XInput back-end).
    if (device_id.find("IG_") != std::string::npos) {
      continue;
    }
    pad.id = device_id;
    pad.usage_page = caps.UsagePage;
    pad.usage = caps.Usage;
    pad.preparsed = preparsed;
    ParseRawCaps(pad, preparsed.data(), preparsed.size());
    fresh.push_back(std::move(pad));
  }

  {
    std::lock_guard<std::mutex> lock(raw_mutex_);
    raw_pads_ = std::move(fresh);
    // Force a state push after enumeration so connect/disconnect reaches Dart.
    latest_raw_signature_.clear();
  }
}

void GamepadBridge::ParseRawCaps(RawPad& pad, const BYTE* preparsed,
                                 size_t size) {
  auto* pre = reinterpret_cast<PHIDP_PREPARSED_DATA>(
      const_cast<BYTE*>(preparsed));
  if (!pre) return;

  // Buttons.
  HIDP_CAPS caps{};
  if (HidP_GetCaps(pre, &caps) != HIDP_STATUS_SUCCESS) {
    return;
  }
  const ULONG btn_cap_count = caps.NumberInputButtonCaps;
  if (btn_cap_count > 0) {
    std::vector<HIDP_BUTTON_CAPS> btn_caps(btn_cap_count);
    USHORT actual = static_cast<USHORT>(btn_cap_count);
    if (HidP_GetButtonCaps(HidP_Input, btn_caps.data(), &actual, pre) ==
        HIDP_STATUS_SUCCESS) {
      std::vector<USHORT> pages, usages;
      for (ULONG i = 0; i < actual; ++i) {
        const HIDP_BUTTON_CAPS& cap = btn_caps[i];
        pages.insert(pages.end(), cap.UsagePage);
        ExpandButtonCaps(cap, usages);
        // pages count must mirror usages count (one per button).
        while (pages.size() < usages.size()) {
          pages.push_back(cap.UsagePage);
        }
      }
      pad.button_pages = pages;
      pad.button_usages = usages;
    }
  }
  pad.button_state.assign(pad.button_usages.size(), 0);

  // Values (analog axes).
  const ULONG value_cap_count = caps.NumberInputValueCaps;
  if (value_cap_count > 0) {
    std::vector<HIDP_VALUE_CAPS> value_caps(value_cap_count);
    USHORT actual = static_cast<USHORT>(value_cap_count);
    if (HidP_GetValueCaps(HidP_Input, value_caps.data(), &actual, pre) ==
        HIDP_STATUS_SUCCESS) {
      for (ULONG i = 0; i < actual; ++i) {
        const HIDP_VALUE_CAPS& cap = value_caps[i];
        if (cap.IsRange) {
          for (USHORT u = cap.Range.UsageMin; u <= cap.Range.UsageMax; ++u) {
            pad.value_pages.push_back(cap.UsagePage);
            pad.value_usages.push_back(u);
            pad.value_min.push_back(cap.LogicalMin);
            pad.value_span.push_back(std::max<int32_t>(
                1, cap.LogicalMax - cap.LogicalMin));
          }
        } else {
          pad.value_pages.push_back(cap.UsagePage);
          pad.value_usages.push_back(cap.NotRange.Usage);
          pad.value_min.push_back(cap.LogicalMin);
          pad.value_span.push_back(
              std::max<int32_t>(1, cap.LogicalMax - cap.LogicalMin));
        }
      }
    }
  }
  pad.axis_state.assign(pad.value_usages.size(), 0.0);
}

void GamepadBridge::UpdateRawPadState(RawPad& pad, const BYTE* report,
                                      ULONG report_len) {
  auto* pre = reinterpret_cast<PHIDP_PREPARSED_DATA>(pad.preparsed.data());
  if (!pre || report_len == 0) {
    return;
  }
  const char* report_ptr = reinterpret_cast<const char*>(report);

  // Buttons: for each distinct page, collect the set of pressed usages and
  // map them back to our expanded button list.
if (!pad.button_usages.empty()) {
    std::vector<uint8_t> pressed(pad.button_usages.size(), 0);
    USHORT page = pad.button_pages[0];
    size_t begin = 0;
    const auto flush = [&](USHORT page, size_t start, size_t end) {
      // Collect pressed usages on this page.
      ULONG count = static_cast<ULONG>(end - start);
      if (count == 0) return;
      std::vector<USHORT> ids(count);
      ULONG actual = count;
      if (HidP_GetUsages(HidP_Input, page, 0, ids.data(), &actual, pre,
                         const_cast<char*>(report_ptr), report_len) ==
          HIDP_STATUS_SUCCESS) {
        for (ULONG i = 0; i < actual; ++i) {
          for (size_t j = start; j < end; ++j) {
            if (pad.button_usages[j] == ids[i]) {
              pressed[j] = 1;
            }
          }
        }
      }
    };
    for (size_t i = 0; i < pad.button_usages.size(); ++i) {
      if (pad.button_pages[i] != page) {
        flush(page, begin, i);
        page = pad.button_pages[i];
        begin = i;
      }
    }
    flush(page, begin, pad.button_usages.size());
    pad.button_state = pressed;
  }

  // Axes: read each usage value and normalize.
  for (size_t a = 0; a < pad.value_usages.size(); ++a) {
    ULONG raw_value = 0;
    const NTSTATUS status = HidP_GetUsageValue(
        HidP_Input, pad.value_pages[a], 0, pad.value_usages[a], &raw_value,
        pre, const_cast<char*>(report_ptr), report_len);
    if (status != HIDP_STATUS_SUCCESS) {
      continue;
    }
    // Normalize into -1..1 centered on the logical midpoint.
    const double min = static_cast<double>(pad.value_min[a]);
    const double span = static_cast<double>(pad.value_span[a]);
    double normalized =
        2.0 * (static_cast<double>(raw_value) - min) / span - 1.0;
    constexpr double kDeadZone = 0.03;
    if (std::fabs(normalized) < kDeadZone) normalized = 0.0;
    normalized = std::max(-1.0, std::min(1.0, normalized));
    pad.axis_state[a] = normalized;
  }
}

void GamepadBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "getGamepads") {
    if (!LoadXInput()) {
      // Even without XInput, raw devices may be present.
    }
    StartPolling();
    RefreshRawDevices();
    StateSnapshot snapshot = ReadSnapshot();
    result->Success(
        flutter::EncodableValue(BuildEncodableGamepads(snapshot)));
    return;
  }
  result->NotImplemented();
}

void GamepadBridge::FlushPendingUpdate() {
  // Called from the platform thread (WM_APP + 1). Send the captured snapshot
  // to the Dart side.
  std::lock_guard<std::mutex> lock(state_mutex_);
  update_pending_ = false;
  channel_->InvokeMethod(
      "onGamepadsUpdate",
      std::make_unique<flutter::EncodableValue>(
          BuildEncodableGamepads(latest_snapshot_)));
}

void GamepadBridge::OnRawInputMessage(HWND hwnd, WPARAM wparam, LPARAM lparam) {
  // wParam is the input code (RIM_INPUT / RIM_INPUTSINK); lParam holds the
  // HRAWINPUT handle.
  if (wparam != RIM_INPUT) {
    return;
  }
  HRAWINPUT raw_input = reinterpret_cast<HRAWINPUT>(lparam);
  UINT size = 0;
  if (GetRawInputData(raw_input, RID_INPUT, nullptr, &size,
                      sizeof(RAWINPUTHEADER)) != 0) {
    return;
  }
  std::vector<BYTE> data(size);
  if (GetRawInputData(raw_input, RID_INPUT, data.data(), &size,
                      sizeof(RAWINPUTHEADER)) != size) {
    return;
  }
  RAWINPUT* raw = reinterpret_cast<RAWINPUT*>(data.data());
  if (raw->header.dwType != RIM_TYPEHID) {
    return;
  }
  const HANDLE device = raw->header.hDevice;
  const BYTE* report = raw->data.hid.bRawData;
  const ULONG report_len = raw->data.hid.dwSizeHid * raw->data.hid.dwCount;

  bool changed = false;
  {
    std::lock_guard<std::mutex> lock(raw_mutex_);
    for (RawPad& pad : raw_pads_) {
      if (pad.device != device) continue;
      const std::string before = pad.Signature();
      UpdateRawPadState(pad, report, report_len);
      if (pad.Signature() != before) {
        changed = true;
      }
      break;
    }
    if (changed) {
      latest_raw_signature_.clear();
    }
  }
  if (changed) {
    PostGamepadUpdate(hwnd_);
  }
}

void GamepadBridge::OnRawInputDeviceChange(WPARAM wparam) {
  RefreshRawDevices();
  PostGamepadUpdate(hwnd_);
}

void GamepadBridge::PollLoop() {
  while (running_) {
    if (!LoadXInput()) {
      Sleep(500);
      continue;
    }
    StateSnapshot snapshot = ReadSnapshot();
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      const std::string raw_sig = [&]() {
        std::lock_guard<std::mutex> rlock(raw_mutex_);
        if (latest_raw_signature_.empty()) {
          std::string s;
          for (const RawPad& pad : raw_pads_) {
            s += pad.Signature();
          }
          latest_raw_signature_ = s;
        }
        return latest_raw_signature_;
      }();
      const std::string combined =
          snapshot.Signature() + "|" + raw_sig;
      if (combined != latest_signature_) {
        latest_signature_ = combined;
        latest_snapshot_ = snapshot;
        update_pending_ = true;
        PostGamepadUpdate(hwnd_);
      }
    }
    // Poll ~10 times per second: enough for button responsiveness while being
    // gentle on the CPU while idle.
    Sleep(100);
  }
}

void GamepadBridge::StartPolling() {
  // Register for Raw Input on the window so non-XInput devices are seen.
  if (hwnd_) {
    RAWINPUTDEVICE raw_device = {};
    raw_device.usUsagePage = kUsagePageGenericDesktop;
    raw_device.usUsage = kUsageGamepad;
    raw_device.dwFlags = RIDEV_INPUTSINK;
    raw_device.hwndTarget = hwnd_;
    RegisterRawInputDevices(&raw_device, 1, sizeof(RAWINPUTDEVICE));

    RAWINPUTDEVICE joystick_device = {};
    joystick_device.usUsagePage = kUsagePageGenericDesktop;
    joystick_device.usUsage = kUsageJoystick;
    joystick_device.dwFlags = RIDEV_INPUTSINK;
    joystick_device.hwndTarget = hwnd_;
    RegisterRawInputDevices(&joystick_device, 1, sizeof(RAWINPUTDEVICE));
  }

  if (running_) return;
  running_ = true;
  poll_thread_ = std::thread(&GamepadBridge::PollLoop, this);
}

flutter::EncodableList GamepadBridge::BuildEncodableGamepads(
    const StateSnapshot& snapshot) {
  using flutter::EncodableMap;
  using flutter::EncodableValue;

  flutter::EncodableList list;

  // XInput controllers first (slots 0..3).
  for (int index = 0; index < kMaxControllers; ++index) {
    const PadSnapshot& pad = snapshot.pads[index];
    if (!pad.connected) continue;

    // Axis order matches the browser Gamepad API: left X/Y, right X/Y,
    // left trigger, right trigger.
    flutter::EncodableList axes;
    axes.push_back(EncodableValue(NormalizeStick(pad.thumb_lx)));
    axes.push_back(EncodableValue(NormalizeStick(pad.thumb_ly)));
    axes.push_back(EncodableValue(NormalizeStick(pad.thumb_rx)));
    axes.push_back(EncodableValue(NormalizeStick(pad.thumb_ry)));
    axes.push_back(EncodableValue(NormalizeTrigger(pad.left_trigger)));
    axes.push_back(EncodableValue(NormalizeTrigger(pad.right_trigger)));

    // Button order per the standard mapping. Each entry is {pressed, touched,
    // value}; browsers expose a value in [0,1] even for digital buttons.
    auto btn = [&pad](bool pressed, double value) {
      EncodableMap map;
      map[EncodableValue("pressed")] = EncodableValue(pressed);
      map[EncodableValue("touched")] = EncodableValue(false);
      map[EncodableValue("value")] = EncodableValue(value);
      return EncodableValue(map);
    };

    flutter::EncodableList buttons;
    buttons.push_back(btn(pad.buttons & kButtonA, 0));
    buttons.push_back(btn(pad.buttons & kButtonB, 0));
    buttons.push_back(btn(pad.buttons & kButtonX, 0));
    buttons.push_back(btn(pad.buttons & kButtonY, 0));
    buttons.push_back(btn(pad.buttons & kLeftShoulder, 0));
    buttons.push_back(btn(pad.buttons & kRightShoulder, 0));
    buttons.push_back(
        btn(pad.left_trigger > 0, NormalizeTrigger(pad.left_trigger)));
    buttons.push_back(
        btn(pad.right_trigger > 0, NormalizeTrigger(pad.right_trigger)));
    buttons.push_back(btn(pad.buttons & kBack, 0));
    buttons.push_back(btn(pad.buttons & kStart, 0));
    buttons.push_back(btn(pad.buttons & kLeftThumb, 0));
    buttons.push_back(btn(pad.buttons & kRightThumb, 0));
    buttons.push_back(btn(pad.buttons & kDpadUp, 0));
    buttons.push_back(btn(pad.buttons & kDpadDown, 0));
    buttons.push_back(btn(pad.buttons & kDpadLeft, 0));
    buttons.push_back(btn(pad.buttons & kDpadRight, 0));

    EncodableMap device;
    device[EncodableValue("id")] =
        EncodableValue("xinput_" + std::to_string(index));
    device[EncodableValue("index")] = EncodableValue(index);
    device[EncodableValue("connected")] = EncodableValue(true);
    device[EncodableValue("timestamp")] =
        EncodableValue(static_cast<int64_t>(GetTickCount64()));
    device[EncodableValue("mapping")] = EncodableValue("standard");
    device[EncodableValue("name")] = EncodableValue("Xbox Controller");
    device[EncodableValue("axes")] = EncodableValue(axes);
    device[EncodableValue("buttons")] = EncodableValue(buttons);

    list.push_back(EncodableValue(device));
  }

  // Raw (non-XInput) HID controllers appended afterwards.
  const int xinput_count = static_cast<int>(list.size());
  std::lock_guard<std::mutex> lock(raw_mutex_);
  for (const RawPad& pad : raw_pads_) {
    // Button order per enumeration. Each entry is {pressed, touched, value}.
    flutter::EncodableList buttons;
    for (size_t b = 0; b < pad.button_usages.size(); ++b) {
      EncodableMap map;
      map[EncodableValue("pressed")] =
          EncodableValue(pad.button_state[b] != 0);
      map[EncodableValue("touched")] = EncodableValue(false);
      map[EncodableValue("value")] =
          EncodableValue(pad.button_state[b] != 0 ? 1.0 : 0.0);
      buttons.push_back(EncodableValue(map));
    }

    flutter::EncodableList axes;
    for (size_t a = 0; a < pad.axis_state.size(); ++a) {
      axes.push_back(EncodableValue(pad.axis_state[a]));
    }

    EncodableMap device;
    device[EncodableValue("id")] =
        EncodableValue("hid_" + std::string(pad.id));
    device[EncodableValue("index")] =
        EncodableValue(xinput_count + static_cast<int>(&pad - raw_pads_.data()));
    device[EncodableValue("connected")] = EncodableValue(true);
    device[EncodableValue("timestamp")] =
        EncodableValue(static_cast<int64_t>(GetTickCount64()));
    device[EncodableValue("mapping")] = EncodableValue("");
    device[EncodableValue("name")] =
        EncodableValue(pad.name.empty() ? "HID Gamepad" : pad.name);
    device[EncodableValue("axes")] = EncodableValue(axes);
    device[EncodableValue("buttons")] = EncodableValue(buttons);

    list.push_back(EncodableValue(device));
  }

  return list;
}