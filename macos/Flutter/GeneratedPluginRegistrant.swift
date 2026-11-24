//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import audio_session
import audio_service
import flutter_secure_storage_darwin
import flutter_soloud
import macos_secure_bookmarks
import package_info_plus
import shared_preferences_foundation
import sqflite_darwin

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AudioSessionPlugin.register(with: registry.registrar(forPlugin: "AudioSessionPlugin"))
  AudioServicePlugin.register(with: registry.registrar(forPlugin: "AudioServicePlugin"))
  FlutterSecureStorageDarwinPlugin.register(with: registry.registrar(forPlugin: "FlutterSecureStorageDarwinPlugin"))
  FlutterSoloudPlugin.register(with: registry.registrar(forPlugin: "FlutterSoloudPlugin"))
  SecureBookmarksPlugin.register(with: registry.registrar(forPlugin: "SecureBookmarksPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
  SqflitePlugin.register(with: registry.registrar(forPlugin: "SqflitePlugin"))
}
