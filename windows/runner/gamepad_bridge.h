#ifndef RUNNER_GAMEPAD_BRIDGE_H_
#define RUNNER_GAMEPAD_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// Bridges gamepads to the Flutter engine through the
// "com.naji.najimessenger/gamepads" method channel.
//
// Two back-ends feed this bridge:
//   * XInput  — polled on a worker thread (Xbox-compatible controllers).
//   * Raw Input (HID) — enumerated, and decoded from WM_INPUT (any HID
//     joystick / gamepad that is *not* an XInput device, e.g. generic USB,
//     DirectInput-style adapters and multi-axis controllers).
//
// Responsibilities:
//   * Handle the "getGamepads" call, returning the currently connected pads.
//   * Push "onGamepadsUpdate" events to the Dart side whenever the connection
//     set or the pad state changes.
class GamepadBridge {
 public:
  GamepadBridge(flutter::BinaryMessenger* messenger, HWND hwnd);
  ~GamepadBridge();

  // Dispatches a method call from the platform channel.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Called from the platform thread when WM_APP + 1 is received; flushes the
  // latest snapshot to Dart.
  void FlushPendingUpdate();

  // Called from the platform thread for WM_INPUT (raw controller data).
  void OnRawInputMessage(HWND hwnd, WPARAM wparam, LPARAM lparam);

  // Called from the platform thread for WM_INPUT_DEVICE_CHANGE.
  void OnRawInputDeviceChange(WPARAM wparam);

  // Starts the XInput polling thread and registers Raw Input on the window.
  void StartPolling();

  // Stops the polling thread. Called from the window OnDestroy path.
  void Shutdown();

 private:
  // Raw state of one XInput controller slot.
  struct PadSnapshot {
    bool connected = false;
    uint32_t packet = 0;
    uint16_t buttons = 0;
    uint8_t left_trigger = 0;
    uint8_t right_trigger = 0;
    int16_t thumb_lx = 0;
    int16_t thumb_ly = 0;
    int16_t thumb_rx = 0;
    int16_t thumb_ry = 0;
  };

  // Snapshot of all four XInput slots.
  struct StateSnapshot {
    PadSnapshot pads[4];

    bool any_connected = false;

    // Compact signature used to detect changes between polls.
    std::string Signature() const;
  };

  // A raw (non-XInput) HID device currently connected.
  struct RawPad {
    HANDLE device = nullptr;
    std::string id;        // RIDI_DEVICENAME (unique per physical device).
    std::string name;      // Product string, else "HID Gamepad".
    ULONG usage_page = 0;
    ULONG usage = 0;

    // Cached preparsed HID data (owned copy for HidP_* parsing).
    std::vector<BYTE> preparsed;

    // Decoded capabilities.
    std::vector<USHORT> button_pages;  // page per digital button group
    std::vector<USHORT> button_usages; // expanded usage ids (one per button)
    std::vector<USHORT> value_pages;   // page per analog axis
    std::vector<USHORT> value_usages;  // usage id per analog axis
    std::vector<int32_t> value_min;    // logical min per axis
    std::vector<int32_t> value_span;   // logical (max-min) per axis

    // Runtime state.
    std::vector<uint8_t> button_state;  // 0/1 per button
    std::vector<double> axis_state;     // normalized -1..1 per axis

    // Compact signature used for change detection.
    std::string Signature() const;
  };

  // Polling loop body.
  void PollLoop();

  // Reads the current XInput state for all four slots.
  StateSnapshot ReadSnapshot() const;

  // Enumeration helpers for Raw Input.
  void RefreshRawDevices();
  void ParseRawCaps(RawPad& pad, const BYTE* preparsed, size_t size);
  void UpdateRawPadState(RawPad& pad, const BYTE* report, ULONG report_len);

  // Builds the EncodableList (one map per connected pad) for the embedded
  // XInput + Raw list as the browser Gamepad API expects.
  flutter::EncodableList BuildEncodableGamepads(
      const StateSnapshot& snapshot);

  // Helpers to load XInput dynamically (avoids hard dependency on xinput.lib).
  bool LoadXInput();
  void UnloadXInput();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND hwnd_;

  // XInput entry point.
  typedef DWORD (*XInputGetStateFn)(DWORD dwUserIndex, void* pState);
  XInputGetStateFn xinput_get_state_ = nullptr;
  HINSTANCE xinput_lib_ = nullptr;

  std::atomic<bool> running_{false};
  std::thread poll_thread_;
  std::mutex state_mutex_;
  StateSnapshot latest_snapshot_;
  std::string latest_signature_;
  bool update_pending_ = false;

  // RawInput state.
  std::mutex raw_mutex_;
  std::vector<RawPad> raw_pads_;
  std::string latest_raw_signature_;
};

#endif  // RUNNER_GAMEPAD_BRIDGE_H_