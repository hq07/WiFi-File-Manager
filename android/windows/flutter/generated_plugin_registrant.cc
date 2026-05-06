//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>
#include <screen_brightness_windows/screen_brightness_windows_plugin.h>
#include <volume_controller/volume_controller_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterSecureStorageWindowsPlugin"));
  ScreenBrightnessWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ScreenBrightnessWindowsPlugin"));
  VolumeControllerPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("VolumeControllerPluginCApi"));
}
