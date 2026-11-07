# REA target routing

| Target | First operation |
|---|---|
| Native executable, DLL, analysis database | `open_binary`, then focused native analysis |
| Managed PE/CLI | `inspect_managed_artifact` |
| Electron/JavaScript tree or ASAR | `analyze_javascript_application` |
| APK code/classes | `inspect_android_package` |
| Archive/package inventory | `open_binary`, then artifact inspection |
| Firmware | `inspect_firmware_regions`; extract only when requested |
| User-owned page already open | `list_browser_targets`, select exact target, then passive observation |
| User-owned Electron runtime | `list_electron_targets`, select exact target |
| HAR/mitmproxy capture | `inspect_web_network_capture` |
| Explicit ELF layout question | `inspect_binary_layout` |
| Ordinary source repository | Source tools; do not run REA |

For large JavaScript or ELF results, request summary detail and inspect retained views. When output truncates, page retained Evidence or export a bundle rather than repeating the producer.

