#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance,
                      _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line,
                      _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // ---------- window size and position (bottom-right) ----------

  // 1. window size (change as you like)
  Win32Window::Size size(320, 100);

  // 2. get work area (screen area without taskbar)
  RECT workArea;
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &workArea, 0);

  // 3. margin from bottom-right corner
  const int margin = 10;

  // 4. calculate window origin (top-left corner) for bottom-right placement
  const int originX =
      workArea.right - static_cast<int>(size.width) - margin;
  const int originY =
      workArea.bottom - static_cast<int>(size.height) - margin;

  Win32Window::Point origin(originX, originY);

  // -------------------------------------------------------------

  // Empty title string keeps the title bar visually minimal.
  if (!window.Create(L"", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
