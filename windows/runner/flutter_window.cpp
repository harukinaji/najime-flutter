#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

// Custom message posted by the GamepadBridge polling thread (WM_APP + 1),
// routed to the platform thread so the method channel can be invoked safely.
static constexpr UINT kGamepadUpdateMessage = WM_APP + 1;

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Bridge XInput gamepads into the "com.naji.najimessenger/gamepads" channel.
  gamepad_bridge_ = std::make_unique<GamepadBridge>(
      flutter_controller_->engine()->messenger(),
      flutter_controller_->view()->GetNativeWindow());
  gamepad_bridge_->StartPolling();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Stop the polling thread before tearing down the engine so no channel call
  // can be dispatched after the messenger is gone.
  if (gamepad_bridge_) {
    gamepad_bridge_->Shutdown();
    gamepad_bridge_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case kGamepadUpdateMessage:
      if (gamepad_bridge_) {
        gamepad_bridge_->FlushPendingUpdate();
      }
      return 0;
    case WM_INPUT:
      if (gamepad_bridge_) {
        gamepad_bridge_->OnRawInputMessage(hwnd, wparam, lparam);
      }
      return 0;
    case WM_INPUT_DEVICE_CHANGE:
      if (gamepad_bridge_) {
        gamepad_bridge_->OnRawInputDeviceChange(wparam);
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
