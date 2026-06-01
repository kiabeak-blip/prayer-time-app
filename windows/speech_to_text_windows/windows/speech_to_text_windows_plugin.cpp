#include "speech_to_text_windows_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <sapi.h>
#include <iostream>
#include <thread>
#include <string>

namespace speech_to_text_windows {

void SpeechToTextWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "speech_to_text_windows",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SpeechToTextWindowsPlugin>();
  plugin->m_channel = std::move(channel);

  // Store the Flutter window handle so we can PostMessage to the UI thread.
  plugin->m_hwnd = registrar->GetView()->GetNativeWindow();

  // Register a window-proc delegate to handle our custom messages on the UI thread.
  plugin->m_proc_delegate_id = registrar->RegisterTopLevelWindowProcDelegate(
      [plugin_pointer = plugin.get()](HWND hwnd, UINT message,
                                      WPARAM wparam, LPARAM lparam)
          -> std::optional<LRESULT> {
        return plugin_pointer->HandleWindowMessage(hwnd, message, wparam, lparam);
      });

  plugin->m_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

// ── Window message handler (runs on UI thread) ────────────────────────────────

std::optional<LRESULT> SpeechToTextWindowsPlugin::HandleWindowMessage(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {

  if (message == WM_STT_RESULT) {
    std::lock_guard<std::mutex> lock(m_result_queue_mutex);
    while (!m_result_queue.empty()) {
      auto [text, is_final] = m_result_queue.front();
      m_result_queue.pop();
      if (m_channel) {
        std::string json = "{\"recognizedWords\":\"" + text +
                           "\",\"finalResult\":" +
                           (is_final ? "true" : "false") + "}";
        m_channel->InvokeMethod(
            "textRecognition",
            std::make_unique<flutter::EncodableValue>(json));
      }
    }
    return 0L;
  }

  if (message == WM_STT_STATUS) {
    std::lock_guard<std::mutex> lock(m_status_queue_mutex);
    while (!m_status_queue.empty()) {
      auto status = m_status_queue.front();
      m_status_queue.pop();
      if (m_channel) {
        m_channel->InvokeMethod(
            "notifyStatus",
            std::make_unique<flutter::EncodableValue>(status));
      }
    }
    return 0L;
  }

  return std::nullopt;
}

// ── Plugin lifecycle ──────────────────────────────────────────────────────────

SpeechToTextWindowsPlugin::SpeechToTextWindowsPlugin()
    : m_cpRecognizer(nullptr),
      m_cpRecoContext(nullptr),
      m_cpRecoGrammar(nullptr),
      m_cpAudio(nullptr),
      m_initialized(false),
      m_listening(false) {
  std::cout << "SpeechToTextWindowsPlugin created" << std::endl;
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
}

SpeechToTextWindowsPlugin::~SpeechToTextWindowsPlugin() {
  std::cout << "SpeechToTextWindowsPlugin destroyed" << std::endl;

  std::lock_guard<std::mutex> lock(m_mutex);

  if (m_listening) {
    Stop(nullptr);
  }

  if (m_cpRecoGrammar) { m_cpRecoGrammar->Release(); m_cpRecoGrammar = nullptr; }
  if (m_cpRecoContext) { m_cpRecoContext->Release(); m_cpRecoContext = nullptr; }
  if (m_cpRecognizer)  { m_cpRecognizer->Release();  m_cpRecognizer  = nullptr; }
  if (m_cpAudio)       { m_cpAudio->Release();       m_cpAudio       = nullptr; }

  CoUninitialize();
}

// ── Method call dispatcher ────────────────────────────────────────────────────

void SpeechToTextWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  const std::string& method_name = method_call.method_name();
  std::cout << "Method called: " << method_name << std::endl;

  if      (method_name == "hasPermission") result->Success(flutter::EncodableValue(true));
  else if (method_name == "initialize")    Initialize(method_call, std::move(result));
  else if (method_name == "listen")        Listen(method_call, std::move(result));
  else if (method_name == "stop")          Stop(std::move(result));
  else if (method_name == "cancel")        Cancel(std::move(result));
  else if (method_name == "locales")       GetLocales(std::move(result));
  else                                     result->NotImplemented();
}

// ── Initialize ────────────────────────────────────────────────────────────────

void SpeechToTextWindowsPlugin::Initialize(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  std::lock_guard<std::mutex> lock(m_mutex);

  if (m_initialized) {
    result->Success(flutter::EncodableValue(true));
    return;
  }

  std::cout << "Initializing SAPI speech recognition..." << std::endl;

  try {
    HRESULT hr = CoCreateInstance(CLSID_SpInprocRecognizer, NULL,
                                   CLSCTX_INPROC_SERVER, IID_ISpRecognizer,
                                   (void**)&m_cpRecognizer);
    if (FAILED(hr)) { result->Success(flutter::EncodableValue(false)); return; }

    hr = CoCreateInstance(CLSID_SpMMAudioIn, NULL, CLSCTX_INPROC_SERVER,
                          IID_ISpAudio, (void**)&m_cpAudio);
    if (FAILED(hr)) { result->Success(flutter::EncodableValue(false)); return; }

    hr = m_cpRecognizer->SetInput(m_cpAudio, TRUE);
    if (FAILED(hr)) { result->Success(flutter::EncodableValue(false)); return; }

    hr = m_cpRecognizer->CreateRecoContext(&m_cpRecoContext);
    if (FAILED(hr)) { result->Success(flutter::EncodableValue(false)); return; }

    hr = m_cpRecoContext->CreateGrammar(0, &m_cpRecoGrammar);
    if (FAILED(hr)) { result->Success(flutter::EncodableValue(false)); return; }

    hr = m_cpRecoGrammar->LoadDictation(NULL, SPLO_STATIC);
    if (FAILED(hr)) { result->Success(flutter::EncodableValue(false)); return; }

    m_initialized = true;
    std::cout << "SAPI speech recognition initialized successfully!" << std::endl;
    result->Success(flutter::EncodableValue(true));

  } catch (...) {
    result->Success(flutter::EncodableValue(false));
  }
}

// ── Listen ────────────────────────────────────────────────────────────────────

void SpeechToTextWindowsPlugin::Listen(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  std::lock_guard<std::mutex> lock(m_mutex);

  if (!m_initialized || !m_cpRecoGrammar) {
    result->Error("NOT_INITIALIZED", "Speech recognition not initialized");
    return;
  }
  if (m_listening) {
    result->Success(flutter::EncodableValue(true));
    return;
  }

  std::cout << "Starting speech recognition..." << std::endl;

  try {
    HRESULT hr = m_cpRecoGrammar->SetDictationState(SPRS_ACTIVE);
    if (FAILED(hr)) { result->Success(flutter::EncodableValue(false)); return; }

    m_listening = true;
    SendStatus("listening");
    std::cout << "Speech recognition listening started!" << std::endl;
    result->Success(flutter::EncodableValue(true));

    // Recognition loop on background thread.
    // Results are marshalled to the UI thread via PostMessage + WM_STT_*.
    std::thread([this]() {
      std::cout << "Recognition thread started" << std::endl;

      SPEVENT event;
      ULONG fetched = 0;

      while (m_listening && m_cpRecoContext) {
        HRESULT hr = m_cpRecoContext->GetEvents(1, &event, &fetched);

        if (SUCCEEDED(hr) && fetched > 0) {
          switch (event.eEventId) {
            case SPEI_RECOGNITION:
            case SPEI_HYPOTHESIS: {
              bool is_final = (event.eEventId == SPEI_RECOGNITION);
              ISpRecoResult* pResult =
                  reinterpret_cast<ISpRecoResult*>(event.lParam);
              if (pResult) {
                LPWSTR pwszText = nullptr;
                hr = pResult->GetText(SP_GETWHOLEPHRASE, SP_GETWHOLEPHRASE,
                                      TRUE, &pwszText, NULL);
                if (SUCCEEDED(hr) && pwszText) {
                  int size = WideCharToMultiByte(CP_UTF8, 0, pwszText, -1,
                                                  nullptr, 0, nullptr, nullptr);
                  if (size > 0) {
                    std::string utf8(size - 1, '\0');
                    WideCharToMultiByte(CP_UTF8, 0, pwszText, -1,
                                        &utf8[0], size, nullptr, nullptr);
                    std::cout << (is_final ? "Recognized" : "Hypothesis")
                              << " text: " << utf8 << std::endl;
                    // Queue + notify UI thread — no direct channel call here.
                    {
                      std::lock_guard<std::mutex> q(m_result_queue_mutex);
                      m_result_queue.push({utf8, is_final});
                    }
                    if (m_hwnd) PostMessage(m_hwnd, WM_STT_RESULT, 0, 0);
                  }
                  CoTaskMemFree(pwszText);
                }
                pResult->Release();
              }
              break;
            }
            case SPEI_SOUND_START:
              SendStatus("soundDetected");
              break;
            case SPEI_SOUND_END:
              SendStatus("soundEnded");
              break;
            default:
              break;
          }
        }

        Sleep(50);
      }

      std::cout << "Recognition thread ended" << std::endl;
    }).detach();

  } catch (...) {
    result->Success(flutter::EncodableValue(false));
  }
}

// ── Stop / Cancel ─────────────────────────────────────────────────────────────

void SpeechToTextWindowsPlugin::Stop(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  std::lock_guard<std::mutex> lock(m_mutex);

  if (m_listening && m_cpRecoGrammar) {
    std::cout << "Stopping speech recognition..." << std::endl;
    m_cpRecoGrammar->SetDictationState(SPRS_INACTIVE);
    m_listening = false;
    SendStatus("notListening");
    std::cout << "Speech recognition stopped" << std::endl;
  }

  if (result) result->Success(flutter::EncodableValue(nullptr));
}

void SpeechToTextWindowsPlugin::Cancel(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  Stop(std::move(result));
}

// ── Locales ───────────────────────────────────────────────────────────────────

void SpeechToTextWindowsPlugin::GetLocales(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  flutter::EncodableList locales;
  locales.push_back(flutter::EncodableValue("en-US:English (United States)"));
  locales.push_back(flutter::EncodableValue("en-GB:English (United Kingdom)"));
  result->Success(flutter::EncodableValue(locales));
}

// ── Thread-safe send helpers ──────────────────────────────────────────────────

void SpeechToTextWindowsPlugin::SendTextRecognition(const std::string& text,
                                                     bool is_final) {
  {
    std::lock_guard<std::mutex> lock(m_result_queue_mutex);
    m_result_queue.push({text, is_final});
  }
  if (m_hwnd) PostMessage(m_hwnd, WM_STT_RESULT, 0, 0);
}

void SpeechToTextWindowsPlugin::SendStatus(const std::string& status) {
  std::cout << "Sending status: " << status << std::endl;
  {
    std::lock_guard<std::mutex> lock(m_status_queue_mutex);
    m_status_queue.push(status);
  }
  if (m_hwnd) PostMessage(m_hwnd, WM_STT_STATUS, 0, 0);
}

void SpeechToTextWindowsPlugin::SendError(const std::string& error) {
  std::cout << "Sending error: " << error << std::endl;
  if (m_channel) {
    m_channel->InvokeMethod(
        "notifyError",
        std::make_unique<flutter::EncodableValue>(error));
  }
}

}  // namespace speech_to_text_windows

extern "C" __declspec(dllexport) void SpeechToTextWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  speech_to_text_windows::SpeechToTextWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
