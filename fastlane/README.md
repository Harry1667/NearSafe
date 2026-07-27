fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios check

```sh
[bundle exec] fastlane ios check
```

預檢：驗證 API 金鑰可登入，並查 App 記錄與 TestFlight 最新建置號

### ios mkcert

```sh
[bundle exec] fastlane ios mkcert
```

探針：測這把 API 金鑰能否在本機建立發布憑證（traditional signing）

### ios beta

```sh
[bundle exec] fastlane ios beta
```

打 Release 包並上傳 TestFlight（正式 APNs 環境）

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

只上傳文字素材（名稱/副標題/描述/關鍵字/URL/審查備註），不動截圖、不動 build、不送審

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
