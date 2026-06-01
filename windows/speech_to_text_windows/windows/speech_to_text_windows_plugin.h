#ifndef FLUTTER_PLUGIN_SPEECH_TO_TEXT_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_SPEECH_TO_TEXT_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <sapi.h>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <optional>

// Custom window messages used to marshal callbacks to the UI thread.
#define WM_STT_RESULT (WM_USER + 100)
#define WM_STT_STATUS (WM_USER + 101)

namespace speech_to_text_windows {

class SpeechToTextWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SpeechToTextWindowsPlugin();
  virtual ~SpeechToTextWindowsPlugin();

  SpeechToTextWindowsPlugin(const SpeechToTextWindowsPlugin&) = delete;
  SpeechToTextWindowsPlugin& operator=(const SpeechToTextWindowsPlugin&) = delete;

  // Window proc delegate — handles WM_STT_* messages on the UI thread.
  std::optional<LRESULT> HandleWindowMessage(HWND hwnd, UINT message,
                                              WPARAM wparam, LPARAM lparam);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void Initialize(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                 std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Listen(const flutter::MethodCall<flutter::EncodableValue> &method_call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Stop(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Cancel(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void GetLocales(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Called from background thread — queues the result and posts WM_STT_RESULT.
  void SendTextRecognition(const std::string& text, bool is_final = false);
  void SendError(const std::string& error);
  // Called from background thread — queues the status and posts WM_STT_STATUS.
  void SendStatus(const std::string& status);

  // SAPI objects
  ISpRecognizer*  m_cpRecognizer;
  ISpRecoContext* m_cpRecoContext;
  ISpRecoGrammar* m_cpRecoGrammar;
  ISpAudio*       m_cpAudio;

  std::mutex m_mutex;
  bool m_initialized;
  bool m_listening;

  // UI-thread marshalling
  HWND m_hwnd = nullptr;
  int  m_proc_delegate_id = -1;

  std::mutex m_result_queue_mutex;
  std::queue<std::pair<std::string, bool>> m_result_queue; // {words, isFinal}

  std::mutex m_status_queue_mutex;
  std::queue<std::string> m_status_queue;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> m_channel;
};

}  // namespace speech_to_text_windows

// C API for Flutter plugin registration
extern "C" __declspec(dllexport) void SpeechToTextWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#endif  // FLUTTER_PLUGIN_SPEECH_TO_TEXT_WINDOWS_PLUGIN_H_
