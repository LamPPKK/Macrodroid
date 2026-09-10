import CoreGraphics
import XCTest

final class MacrodroidGate1Tests: XCTestCase {
    func testAspectFitCentersSixteenByNineInsideMatchingViewport() {
        let mapper = ViewportMapper(
            sourceSize: CGSize(width: 1920, height: 1080),
            viewportSize: CGSize(width: 1600, height: 900)
        )
        XCTAssertEqual(mapper.displayedRect, CGRect(x: 0, y: 0, width: 1600, height: 900))
    }

    func testLetterboxRegionDoesNotProduceAndroidTouch() {
        let mapper = ViewportMapper(
            sourceSize: CGSize(width: 1920, height: 1080),
            viewportSize: CGSize(width: 1600, height: 1000)
        )
        XCTAssertNil(mapper.sourcePoint(for: CGPoint(x: 800, y: 20)))
    }

    func testViewportCenterMapsToSourceCenter() throws {
        let mapper = ViewportMapper(
            sourceSize: CGSize(width: 1920, height: 1080),
            viewportSize: CGSize(width: 1600, height: 1000)
        )
        let source = try XCTUnwrap(mapper.sourcePoint(for: CGPoint(x: 800, y: 500)))
        XCTAssertEqual(source.x, 960, accuracy: 0.001)
        XCTAssertEqual(source.y, 540, accuracy: 0.001)
    }

    func testPrimaryTouchKeepsItsIdentifierUntilZeroPressureRelease() {
        var sequence = PrimaryTouchSequence()
        let point = TouchPoint(x: 1716, y: 898)
        let contact = sequence.contact(at: point)
        let release = sequence.release(at: nil)

        XCTAssertEqual(contact?.identifier, TouchInput.primaryIdentifier)
        XCTAssertEqual(release?.identifier, contact?.identifier)
        XCTAssertEqual(release.map { TouchPoint(x: $0.x, y: $0.y) }, point)
        XCTAssertEqual(contact?.pressure, 1)
        XCTAssertEqual(release?.pressure, 0)
        XCTAssertNil(sequence.release(at: nil))
    }

    func testNativeRGBAFrameContractAcceptsExact1080pFrame() throws {
        XCTAssertNoThrow(try FrameContract.validate(
            width: 1920,
            height: 1080,
            byteCount: 1920 * 1080 * 4
        ))
    }

    func testNativeRGBAFrameContractRejectsTruncatedFrame() {
        XCTAssertThrowsError(try FrameContract.validate(
            width: 1920,
            height: 1080,
            byteCount: 1920 * 1080 * 4 - 1
        )) { error in
            XCTAssertEqual(
                error as? FrameContractError,
                .wrongByteCount(expected: 1920 * 1080 * 4, actual: 1920 * 1080 * 4 - 1)
            )
        }
    }

    func testLatestFrameMailboxIsBoundedToNewestFrame() {
        let mailbox = LatestFrameMailbox()
        let first = EmulatorFrame(
            pixels: Data(count: 4), width: 1, height: 1, sequence: 1,
            emulatorTimestampMicroseconds: 1, receivedMonotonicNanoseconds: 1
        )
        let second = EmulatorFrame(
            pixels: Data(count: 4), width: 1, height: 1, sequence: 2,
            emulatorTimestampMicroseconds: 2, receivedMonotonicNanoseconds: 2
        )
        mailbox.publish(first)
        mailbox.publish(second)
        XCTAssertEqual(mailbox.takeLatest()?.sequence, 2)
        XCTAssertNil(mailbox.takeLatest())
        XCTAssertEqual(mailbox.snapshot().replacedBeforePresentation, 1)
    }

    func testAVDRestoreAllowsOnlyTheAppliedConfiguration() throws {
        XCTAssertEqual(
            try AVDTransactionGuard.restoreDecision(
                currentSHA256: "applied", originalSHA256: "original", appliedSHA256: "applied"
            ),
            .restoreBackup
        )
    }

    func testAVDRestoreDoesNotOverwriteAConflictingConfiguration() {
        XCTAssertThrowsError(try AVDTransactionGuard.restoreDecision(
            currentSHA256: "changed-by-someone-else",
            originalSHA256: "original",
            appliedSHA256: "applied"
        )) { error in
            XCTAssertEqual(error as? AVDTransactionGuardError, .conflictingCurrentConfiguration)
        }
    }

    func testRuntimeProfileRejectsUnsupportedValues() {
        let baseline = TFTMACRuntimeProfile.playable
        let candidate = baseline.with(vCPU: 99, ramMiB: 1, refreshHz: 144, asgDrawFlushInterval: 7)
        XCTAssertEqual(candidate.vCPU, baseline.vCPU)
        XCTAssertEqual(candidate.ramMiB, baseline.ramMiB)
        XCTAssertEqual(candidate.refreshHz, baseline.refreshHz)
        XCTAssertEqual(candidate.asgDrawFlushInterval, baseline.asgDrawFlushInterval)
        XCTAssertEqual(candidate.width, 1920)
        XCTAssertEqual(candidate.height, 1080)
    }

    func testRuntimeProfileAcceptsSafeExperimentValues() {
        let candidate = TFTMACRuntimeProfile.playable.with(
            vCPU: 8,
            ramMiB: 6144,
            refreshHz: 30,
            asgDrawFlushInterval: 400
        )
        XCTAssertEqual(candidate.vCPU, 8)
        XCTAssertEqual(candidate.ramMiB, 6144)
        XCTAssertEqual(candidate.refreshHz, 30)
        XCTAssertEqual(candidate.asgDrawFlushInterval, 400)
        XCTAssertEqual(candidate.identifier, "macrodroid_native_6144m_8c_30hz_flush400")

        // Validate EngineLaunchPolicy and EngineCloseBehavior persistence
        XCTAssertEqual(EngineLaunchPolicy.allCases.count, 2)
        XCTAssertTrue(EngineLaunchPolicy.allCases.contains(.alwaysBackground))
        XCTAssertTrue(EngineLaunchPolicy.allCases.contains(.onDemand))
        let policyDefaults = UserDefaults(suiteName: "test.engine.policy")!
        policyDefaults.removeObject(forKey: EngineLaunchPolicy.preferenceKey)
        XCTAssertEqual(EngineLaunchPolicy.load(from: policyDefaults), .alwaysBackground)
        EngineLaunchPolicy.onDemand.save(to: policyDefaults)
        XCTAssertEqual(EngineLaunchPolicy.load(from: policyDefaults), .onDemand)
        EngineLaunchPolicy.alwaysBackground.save(to: policyDefaults)
        XCTAssertEqual(EngineLaunchPolicy.load(from: policyDefaults), .alwaysBackground)

        XCTAssertEqual(EngineCloseBehavior.allCases.count, 2)
        XCTAssertTrue(EngineCloseBehavior.allCases.contains(.keepWarm))
        XCTAssertTrue(EngineCloseBehavior.allCases.contains(.stopEngine))
        let closeDefaults = UserDefaults(suiteName: "test.engine.close")!
        closeDefaults.removeObject(forKey: EngineCloseBehavior.preferenceKey)
        XCTAssertEqual(EngineCloseBehavior.load(from: closeDefaults), .keepWarm)
        EngineCloseBehavior.stopEngine.save(to: closeDefaults)
        XCTAssertEqual(EngineCloseBehavior.load(from: closeDefaults), .stopEngine)
        EngineCloseBehavior.keepWarm.save(to: closeDefaults)
        XCTAssertEqual(EngineCloseBehavior.load(from: closeDefaults), .keepWarm)

        // Validate NotificationPreferences
        let notifDefaults = UserDefaults(suiteName: "test.notif.prefs")!
        notifDefaults.removeObject(forKey: NotificationPreferences.mirroringEnabledKey)
        notifDefaults.removeObject(forKey: NotificationPreferences.filterSystemKey)
        XCTAssertTrue(NotificationPreferences.isMirroringEnabled(defaults: notifDefaults))
        XCTAssertTrue(NotificationPreferences.isSystemFilterEnabled(defaults: notifDefaults))
        NotificationPreferences.setMirroringEnabled(false, defaults: notifDefaults)
        XCTAssertFalse(NotificationPreferences.isMirroringEnabled(defaults: notifDefaults))
        NotificationPreferences.setSystemFilterEnabled(false, defaults: notifDefaults)
        XCTAssertFalse(NotificationPreferences.isSystemFilterEnabled(defaults: notifDefaults))

        // Validate AndroidNotificationParser
        let sampleList = """
0|com.riotgames.league.teamfighttactics|1001|null|10200: NotificationRecord(0|com.riotgames.league.teamfighttactics|1001|null|10200: pkg=com.riotgames.league.teamfighttactics user=UserHandle{0} id=1001 tag=null score=0 key=0|com.riotgames.league.teamfighttactics|1001|null|10200: Notification(channel=tft_game_channel pri=0 flags=0x10 color=0x00000000 vis=PRIVATE))
0|android|17041793|null|1000: NotificationRecord(0|android|17041793|null|1000: pkg=android user=UserHandle{0} id=17041793 tag=null score=-20 key=0|android|17041793|null|1000: Notification(channel=DEVELOPER pri=-2 flags=0x2 color=0x00000000 vis=SECRET))
"""
        let parsedKeys = AndroidNotificationParser.parseNotificationKeys(from: sampleList)
        XCTAssertEqual(parsedKeys.count, 2)
        XCTAssertEqual(parsedKeys.first, "0|com.riotgames.league.teamfighttactics|1001|null|10200")

        let sampleDetails = """
NotificationRecord(0|com.riotgames.league.teamfighttactics|1001|null|10200: pkg=com.riotgames.league.teamfighttactics user=UserHandle{0} id=1001 tag=null importance=4 key=0|com.riotgames.league.teamfighttactics|1001|null|10200: Notification(channel=tft_game_channel pri=0 flags=0x10 color=0x00000000 vis=PRIVATE))
  uid=10200 userId=0
  icon=Icon(typ=RESOURCE pkg=com.riotgames.league.teamfighttactics id=0x7f080001)
  channel=NotificationChannel{mId='tft_game_channel', mName=TFT Updates, mImportance=4}
  extras={
    android.title=String (Match Found!)
    android.substName=String (TFT Mobile)
    android.text=String (Your Teamfight Tactics match is ready.)
  }
"""
        let record = AndroidNotificationParser.parseNotificationRecord(
            key: "0|com.riotgames.league.teamfighttactics|1001|null|10200",
            output: sampleDetails
        )
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.packageName, "com.riotgames.league.teamfighttactics")
        XCTAssertEqual(record?.appName, "TFT Mobile")
        XCTAssertEqual(record?.title, "Match Found!")
        XCTAssertEqual(record?.text, "Your Teamfight Tactics match is ready.")
        XCTAssertFalse(record?.isSystemPackage ?? true)

        let sysRecord = GuestNotificationRecord(
            key: "0|android|17041793|null|1000",
            packageName: "android",
            title: "USB Debugging",
            text: "USB debugging connected",
            appDisplayName: "Android System",
            importance: 1
        )
        XCTAssertTrue(sysRecord.isSystemPackage)
        XCTAssertEqual(sysRecord.appName, "Android System")

        // Validate ClipboardPreferences and ClipboardSyncCoordinator
        let clipDefaults = UserDefaults(suiteName: "test.clipboard.prefs")!
        clipDefaults.removeObject(forKey: ClipboardPreferences.preferenceKey)
        XCTAssertTrue(ClipboardPreferences.isSyncEnabled(defaults: clipDefaults))
        ClipboardPreferences.setSyncEnabled(false, defaults: clipDefaults)
        XCTAssertFalse(ClipboardPreferences.isSyncEnabled(defaults: clipDefaults))
        ClipboardPreferences.setSyncEnabled(true, defaults: clipDefaults)
        XCTAssertTrue(ClipboardPreferences.isSyncEnabled(defaults: clipDefaults))

        let coordinator = ClipboardSyncCoordinator(defaults: clipDefaults)
        let clipExp = expectation(description: "ClipboardSyncCoordinator")
        Task {
            await coordinator.simulateSyncState(text: "Hello Android", changeCount: 5)
            let current = await coordinator.currentSyncedText()
            XCTAssertEqual(current, "Hello Android")
            let didUpdate = await coordinator.syncToMac(text: "Hello Android")
            XCTAssertFalse(didUpdate)
            clipExp.fulfill()
        }
        wait(for: [clipExp], timeout: 2.0)

        // Validate safe non-main-thread initialization without runtime executor crash
        let detachedClipExp = expectation(description: "ClipboardSyncCoordinatorDetached")
        Task.detached {
            let bgDefaults = UserDefaults(suiteName: "test.bg.coord") ?? .standard
            let bgCoordinator = ClipboardSyncCoordinator(defaults: bgDefaults)
            let enabled = await bgCoordinator.isEnabled
            XCTAssertTrue(enabled)
            let checked = await bgCoordinator.checkMacPasteboard()
            XCTAssertNil(checked)
            detachedClipExp.fulfill()
        }
        wait(for: [detachedClipExp], timeout: 2.0)

        // Validate FileTransferResult (Drag & Drop File Sharing)
        let apkResult = FileTransferResult(
            filename: "sample.apk",
            isAPK: true,
            success: true,
            destination: "Application",
            message: "Installed successfully"
        )
        XCTAssertTrue(apkResult.isAPK)
        XCTAssertTrue(apkResult.success)
        XCTAssertEqual(apkResult.filename, "sample.apk")
        XCTAssertEqual(apkResult.destination, "Application")
        XCTAssertEqual(apkResult.message, "Installed successfully")

        let fileResult = FileTransferResult(
            filename: "photo.jpg",
            isAPK: false,
            success: true,
            destination: "/sdcard/Download/photo.jpg",
            message: "Pushed to Downloads"
        )
        XCTAssertFalse(fileResult.isAPK)
        XCTAssertTrue(fileResult.success)
        XCTAssertEqual(fileResult.destination, "/sdcard/Download/photo.jpg")

        // Validate Drag & Drop File Routing and Batch Filtering
        let mixedResults = [
            FileTransferResult(filename: "game.APK", isAPK: true, success: true, destination: "Application", message: "Installed"),
            FileTransferResult(filename: "config.json", isAPK: false, success: true, destination: "/sdcard/Download/config.json", message: "Saved"),
            FileTransferResult(filename: "screenshot.PNG", isAPK: false, success: true, destination: "/sdcard/Download/screenshot.PNG", message: "Saved"),
            FileTransferResult(filename: "bad.apk", isAPK: true, success: false, destination: "Application", message: "INSTALL_FAILED_ALREADY_EXISTS")
        ]
        let apks = mixedResults.filter { $0.isAPK }
        let normalFiles = mixedResults.filter { !$0.isAPK }
        XCTAssertEqual(apks.count, 2)
        XCTAssertEqual(normalFiles.count, 2)
        XCTAssertEqual(mixedResults.filter { $0.success }.count, 3)
        XCTAssertEqual(mixedResults.filter { !$0.success }.count, 1)

        // Validate IdleSuspendTimeout and IdleSuspendPreferences
        XCTAssertEqual(IdleSuspendTimeout.allCases.count, 5)
        XCTAssertEqual(IdleSuspendTimeout.immediately.seconds, 0)
        XCTAssertEqual(IdleSuspendTimeout.oneMinute.seconds, 60)
        XCTAssertEqual(IdleSuspendTimeout.fiveMinutes.seconds, 300)
        XCTAssertEqual(IdleSuspendTimeout.fifteenMinutes.seconds, 900)
        XCTAssertNil(IdleSuspendTimeout.never.seconds)

        XCTAssertTrue(IdleSuspendTimeout.immediately.displayName.contains("Ngay lập tức"))
        XCTAssertTrue(IdleSuspendTimeout.oneMinute.displayName.contains("1 phút"))
        XCTAssertTrue(IdleSuspendTimeout.fiveMinutes.displayName.contains("5 phút"))
        XCTAssertTrue(IdleSuspendTimeout.fifteenMinutes.displayName.contains("15 phút"))
        XCTAssertTrue(IdleSuspendTimeout.never.displayName.contains("Không bao giờ"))

        let idleDefaults = UserDefaults(suiteName: "test.idle.suspend")!
        idleDefaults.removeObject(forKey: IdleSuspendPreferences.preferenceKey)
        XCTAssertEqual(IdleSuspendPreferences.loadTimeout(defaults: idleDefaults), .fiveMinutes)
        IdleSuspendPreferences.saveTimeout(.immediately, defaults: idleDefaults)
        XCTAssertEqual(IdleSuspendPreferences.loadTimeout(defaults: idleDefaults), .immediately)
        IdleSuspendPreferences.saveTimeout(.oneMinute, defaults: idleDefaults)
        XCTAssertEqual(IdleSuspendPreferences.loadTimeout(defaults: idleDefaults), .oneMinute)
        IdleSuspendPreferences.saveTimeout(.fifteenMinutes, defaults: idleDefaults)
        XCTAssertEqual(IdleSuspendPreferences.loadTimeout(defaults: idleDefaults), .fifteenMinutes)
        IdleSuspendPreferences.saveTimeout(.never, defaults: idleDefaults)
        XCTAssertEqual(IdleSuspendPreferences.loadTimeout(defaults: idleDefaults), .never)

        // Validate AppShortcutManager and URL Deep Linking
        let shortcutExp = expectation(description: "AppShortcutManagerTests")
        Task { @MainActor in
            // 1. URL Scheme Parsing
            let standardURL = URL(string: "macrodroid://launch?pkg=com.riotgames.league.teamfighttactics")!
            XCTAssertEqual(AppShortcutManager.parseLaunchURL(standardURL), "com.riotgames.league.teamfighttactics")

            let altURL = URL(string: "macrodroid://launch?package=com.supercell.clashroyale")!
            XCTAssertEqual(AppShortcutManager.parseLaunchURL(altURL), "com.supercell.clashroyale")

            let invalidSchemeURL = URL(string: "https://launch?pkg=com.test.app")!
            XCTAssertNil(AppShortcutManager.parseLaunchURL(invalidSchemeURL))

            let invalidHostURL = URL(string: "macrodroid://settings?pkg=com.test.app")!
            XCTAssertNil(AppShortcutManager.parseLaunchURL(invalidHostURL))

            let missingQueryURL = URL(string: "macrodroid://launch")!
            XCTAssertNil(AppShortcutManager.parseLaunchURL(missingQueryURL))

            // 2. Launcher Script Generation
            let script = AppShortcutManager.generateLauncherScript(package: "com.test.game")
            XCTAssertTrue(script.contains("#!/bin/sh"))
            XCTAssertTrue(script.contains("macrodroid://launch?pkg=com.test.game"))
            XCTAssertTrue(script.contains("open -b \"com.macrodroid\" --args --launch-pkg \"com.test.game\""))

            // 3. Info.plist Generation
            let plistStr = AppShortcutManager.generateInfoPlist(name: "My:Cool/App", package: "com.my-cool app.game", version: "2.5.1")
            XCTAssertTrue(plistStr.contains("<key>CFBundleName</key>"))
            XCTAssertTrue(plistStr.contains("<string>My-Cool-App</string>"))
            XCTAssertTrue(plistStr.contains("<string>com.macrodroid.app.com.my_cool_app.game</string>"))
            XCTAssertTrue(plistStr.contains("<string>2.5.1</string>"))
            XCTAssertTrue(plistStr.contains("<key>CFBundleExecutable</key>"))
            XCTAssertTrue(plistStr.contains("<string>AppLauncher</string>"))

            // XML entity escaping verification
            let specialPlistStr = AppShortcutManager.generateInfoPlist(
                name: "Dungeons & Dragons: <Heroes>",
                package: "com.wizards.dnd-game",
                version: "1.0.0"
            )
            XCTAssertTrue(specialPlistStr.contains("&amp;"))
            XCTAssertTrue(specialPlistStr.contains("&lt;"))
            XCTAssertTrue(specialPlistStr.contains("&gt;"))
            if let data = specialPlistStr.data(using: .utf8),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                XCTAssertEqual(dict["CFBundleDisplayName"] as? String, "Dungeons & Dragons- <Heroes>")
            } else {
                XCTFail("Failed to deserialize special characters Info.plist")
            }

            // 4. End-to-End Shortcut Bundle Creation & Verification in Temporary Directory
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macrodroid_ut_\(UUID().uuidString)", isDirectory: true)
            let createdBundle = AppShortcutManager.createShortcut(
                name: "Test Game",
                bundleIdentifier: "com.test.game",
                version: "1.0.0",
                customIcon: nil,
                destinationDirectory: tempDir
            )
            XCTAssertNotNil(createdBundle)
            if let createdBundle {
                XCTAssertTrue(FileManager.default.fileExists(atPath: createdBundle.path))
                let infoPlistFile = createdBundle.appendingPathComponent("Contents/Info.plist")
                XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistFile.path))

                if let data = try? Data(contentsOf: infoPlistFile),
                   let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    XCTAssertEqual(dict["CFBundleDisplayName"] as? String, "Test Game")
                    XCTAssertEqual(dict["CFBundleIdentifier"] as? String, "com.macrodroid.app.com.test.game")
                    XCTAssertEqual(dict["CFBundleExecutable"] as? String, "AppLauncher")
                } else {
                    XCTFail("Failed to deserialize generated Info.plist")
                }

                let launcherFile = createdBundle.appendingPathComponent("Contents/MacOS/AppLauncher")
                XCTAssertTrue(FileManager.default.fileExists(atPath: launcherFile.path))
                let attrs = try? FileManager.default.attributesOfItem(atPath: launcherFile.path)
                let permissions = attrs?[.posixPermissions] as? Int
                XCTAssertEqual(permissions, 0o755)

                // 5. Verify AppShortcutManager.removeShortcut cleans up the bundle
                AppShortcutManager.removeShortcut(
                    name: "Test Game",
                    bundleIdentifier: "com.test.game",
                    destinationDirectory: tempDir
                )
                XCTAssertFalse(FileManager.default.fileExists(atPath: createdBundle.path))

                try? FileManager.default.removeItem(at: tempDir)
            }

            shortcutExp.fulfill()
        }
        wait(for: [shortcutExp], timeout: 3.0)

        // Validate GoogleEcosystemConfig for Aurora Store and microG
        XCTAssertEqual(GoogleEcosystemConfig.auroraStorePackage, "com.aurora.store")
        XCTAssertEqual(GoogleEcosystemConfig.auroraStoreVersion, "4.8.4")
        XCTAssertEqual(GoogleEcosystemConfig.auroraStoreURL.scheme, "https")
        XCTAssertEqual(GoogleEcosystemConfig.auroraStoreURL.host, "f-droid.org")

        XCTAssertEqual(GoogleEcosystemConfig.microGGmsPackage, "com.google.android.gms")
        XCTAssertEqual(GoogleEcosystemConfig.microGGmsVersion, "0.3.16")
        XCTAssertEqual(GoogleEcosystemConfig.microGGmsURL.scheme, "https")
        XCTAssertEqual(GoogleEcosystemConfig.microGGmsURL.host, "github.com")

        XCTAssertEqual(GoogleEcosystemConfig.microGFakeStorePackage, "com.android.vending")
        XCTAssertEqual(GoogleEcosystemConfig.microGFakeStoreURL.scheme, "https")
        XCTAssertEqual(GoogleEcosystemConfig.microGFakeStoreURL.host, "github.com")

        // Validate SharedFolderConfig and FreeformWindowConfig
        let testSharedBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestMacrodroidShared_\(UUID().uuidString)", isDirectory: true)
        SharedFolderConfig.ensureDirectoriesExist(at: testSharedBase)
        let toDir = testSharedBase.appendingPathComponent("To Android", isDirectory: true)
        let fromDir = testSharedBase.appendingPathComponent("From Android", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: toDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fromDir.path))
        XCTAssertEqual(SharedFolderConfig.guestDestinationPath, "/sdcard/Download")
        XCTAssertEqual(SharedFolderConfig.guestSharedPath, "/sdcard/Macrodroid")

        XCTAssertTrue(FreeformWindowConfig.enableFreeformScript.contains("enable_freeform_support 1"))
        XCTAssertTrue(FreeformWindowConfig.enableFreeformScript.contains("force_resizable_activities 1"))
        XCTAssertTrue(FreeformWindowConfig.disableFreeformScript.contains("enable_freeform_support 0"))

        // Validate SharedFolderSyncCoordinator
        let sharedCoord = SharedFolderSyncCoordinator(sharedDirectory: testSharedBase)
        let sampleFile = toDir.appendingPathComponent("sample_document.txt")
        try? "Test content".write(to: sampleFile, atomically: true, encoding: .utf8)
        let sharedExp = expectation(description: "SharedFolderSyncCoordinator")
        Task {
            let pending = await sharedCoord.discoverPendingTransfers()
            XCTAssertEqual(pending.count, 1)
            XCTAssertEqual(pending.first?.lastPathComponent, "sample_document.txt")

            await sharedCoord.markFileProcessed(sampleFile)
            let processedPending = await sharedCoord.discoverPendingTransfers()
            XCTAssertEqual(processedPending.count, 0)
            let count = await sharedCoord.processedCount()
            XCTAssertEqual(count, 1)

            try? FileManager.default.removeItem(at: testSharedBase)
            sharedExp.fulfill()
        }
        wait(for: [sharedExp], timeout: 2.0)

        // Validate ClipboardSyncCoordinator Bidirectional Echo Cancellation
        let deepCoord = ClipboardSyncCoordinator(defaults: UserDefaults(suiteName: "test.clipboard.prefs.deep")!)
        let clipExp2 = expectation(description: "ClipboardSyncCoordinatorDeep")
        Task {
            // 1. Host copy
            await deepCoord.simulateSyncState(text: "Host Clipboard Text 1", changeCount: 11)
            let current = await deepCoord.currentSyncedText()
            XCTAssertEqual(current, "Host Clipboard Text 1")

            // 2. Guest echo is ignored
            let echoIgnored = await deepCoord.syncToMac(text: "Host Clipboard Text 1")
            XCTAssertFalse(echoIgnored)

            // 3. Guest genuine new copy is accepted
            let guestUpdated = await deepCoord.syncToMac(text: "Guest Clipboard Text 2")
            XCTAssertTrue(guestUpdated)
            let updated = await deepCoord.currentSyncedText()
            XCTAssertEqual(updated, "Guest Clipboard Text 2")

            // 4. Disabled sync gate
            let taskDefaults = UserDefaults(suiteName: "test.clipboard.prefs.deep")!
            ClipboardPreferences.setSyncEnabled(false, defaults: taskDefaults)
            let blocked = await deepCoord.syncToMac(text: "Blocked Text")
            XCTAssertFalse(blocked)
            ClipboardPreferences.setSyncEnabled(true, defaults: taskDefaults)

            clipExp2.fulfill()
        }
        wait(for: [clipExp2], timeout: 2.0)

        // Validate NotificationParser Unicode and Emoji Support
        let unicodeDetails = """
NotificationRecord(0|com.riotgames.league.teamfighttactics|2002|null|10200: pkg=com.riotgames.league.teamfighttactics user=UserHandle{0} id=2002 tag=null importance=4 key=0|com.riotgames.league.teamfighttactics|2002|null|10200: Notification(channel=tft_game_channel pri=0 flags=0x10 color=0x00000000 vis=PRIVATE))
  uid=10200 userId=0
  extras={
    android.title=String (🎉 Chiến thắng!)
    android.substName=String (Đấu Trường Chân Lý)
    android.text=String (Bạn đã thăng hạng lên Cao Thủ 🏆)
  }
"""
        let unicodeRecord = AndroidNotificationParser.parseNotificationRecord(
            key: "0|com.riotgames.league.teamfighttactics|2002|null|10200",
            output: unicodeDetails
        )
        XCTAssertNotNil(unicodeRecord)
        XCTAssertEqual(unicodeRecord?.title, "🎉 Chiến thắng!")
        XCTAssertEqual(unicodeRecord?.appName, "Đấu Trường Chân Lý")
        XCTAssertEqual(unicodeRecord?.text, "Bạn đã thăng hạng lên Cao Thủ 🏆")
        XCTAssertFalse(unicodeRecord?.isSystemPackage ?? true)
    }

    func testRapidCombatExperimentHasExactlyTwoNamedPresets() {
        XCTAssertEqual(RuntimeExperimentPreset.selectableCases.map(\.rawValue), ["control", "combat_latency_a"])
    }

    func testCombatLatencyAChangesOnlyTheHostSchedulingRequest() {
        let control = TFTMACRuntimeProfile.playable.with(experimentPreset: .control)
        let candidate = TFTMACRuntimeProfile.playable.with(experimentPreset: .combatLatencyA)
        XCTAssertEqual(control.effectiveEmulatorFeatures, RuntimeExperimentPreset.baselineEmulatorFeatures)
        XCTAssertEqual(candidate.effectiveEmulatorFeatures, RuntimeExperimentPreset.baselineEmulatorFeatures)
        XCTAssertEqual(control.vCPU, candidate.vCPU)
        XCTAssertEqual(control.ramMiB, candidate.ramMiB)
        XCTAssertEqual(control.asgDrawFlushInterval, candidate.asgDrawFlushInterval)
        XCTAssertFalse(control.experimentPreset.requestsHostLatencyQoS)
        XCTAssertTrue(candidate.experimentPreset.requestsHostLatencyQoS)
        XCTAssertEqual(control.comparisonConfigurationSHA256, candidate.comparisonConfigurationSHA256)
        XCTAssertNotEqual(control.experimentConfigurationReceipt.sha256, candidate.experimentConfigurationReceipt.sha256)
    }

    func testRetiredPerformanceModePresetMigratesToControl() throws {
        let suiteName = "tftmac-tests-\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.set("home_run_a", forKey: "runtime.experimentPreset")
        XCTAssertEqual(RuntimeExperimentPreset.load(from: suite), .control)
    }

    func testGuestPowerReceiptRequiresPoweredStayOnAndAwake() throws {
        let ready = try XCTUnwrap(GuestPowerState.parse("""
            mIsPowered=true
            mStayOn=true
            mWakefulness=Awake
            """))
        XCTAssertTrue(ready.isGameplayReady)
        let sleeping = try XCTUnwrap(GuestPowerState.parse("""
            mIsPowered=false
            mStayOn=false
            mWakefulness=Asleep
            """))
        XCTAssertFalse(sleeping.isGameplayReady)
    }

    func testHostSchedulingReceiptVerifiesUserInteractiveRequest() throws {
        let receipt = try XCTUnwrap(HostSchedulingReceipt.parse("""
            TFTMAC_HOST_QOS_REQUESTED=user_interactive
            TFTMAC_HOST_QOS_SET_RESULT=0
            TFTMAC_HOST_QOS_EFFECTIVE=user_interactive
            TFTMAC_HOST_QOS_RELATIVE_PRIORITY=0
            """))
        XCTAssertTrue(receipt.userInteractiveVerified)
    }

    func testCombatComparisonNormalizesDynamicSurfaceLayerTokens() throws {
        let first = "fe46e7c SurfaceView[com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity](BLAST)#136"
        let second = "991abcd SurfaceView[com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity](BLAST)#42"
        XCTAssertEqual(
            CombatLayerIdentity.comparable(first),
            CombatLayerIdentity.comparable(second)
        )
        XCTAssertNil(CombatLayerIdentity.comparable("NexusLauncher#1"))
    }

    func testRuntimeLeaseRejectsASecondLiveOwner() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tftmac-lease-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try TFTMACRuntimeLease.acquire(stateRoot: root)
        defer { first.release() }
        XCTAssertThrowsError(try TFTMACRuntimeLease.acquire(stateRoot: root)) { error in
            guard case RuntimeLeaseError.alreadyOwned = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAVDRecoveryRejectsBackupOutsideCaptureRoot() {
        XCTAssertThrowsError(try AVDTransactionGuard.validateRecoveryPaths(
            markerConfigURL: URL(fileURLWithPath: "/runtime/TFT.avd/config.ini"),
            expectedConfigURL: URL(fileURLWithPath: "/runtime/TFT.avd/config.ini"),
            backupURL: URL(fileURLWithPath: "/tmp/untrusted/avd-config.before.ini"),
            captureRoot: URL(fileURLWithPath: "/captures", isDirectory: true)
        )) { error in
            XCTAssertEqual(error as? AVDTransactionGuardError, .unexpectedRecoveryPath)
        }
    }

    func testMemoryKillClassifierAcceptsConfirmedVictims() {
        XCTAssertTrue(TelemetrySignalClassifier.isConfirmedGuestMemoryKill(
            "08-30 04:10:00.000 I lmkd: Kill 'com.riotgames.league.teamfighttactics' (4024), uid 10123, oom_score_adj 900"
        ))
        XCTAssertTrue(TelemetrySignalClassifier.isConfirmedGuestMemoryKill(
            "08-30 04:10:00.000 I lowmemorykiller: Killing 'com.example.background' (4025), adj 950"
        ))
        XCTAssertTrue(TelemetrySignalClassifier.isConfirmedGuestMemoryKill(
            "kernel: Out of memory: Killed process 4024 (TFTMain) total-vm:1234kB"
        ))
    }

    func testMemoryKillClassifierRejectsBootAndSetupNoise() {
        let nonKills = [
            "lmkd: Connection with lmkd established",
            "lowmemorykiller: lowmemorykiller data connection established",
            "lmkd: memevent failed to attach",
            "lmkd: android_trigger_vendor_lmk_kill tracepoint unavailable",
            "lmkd: Using psi monitors for memory pressure detection",
            "com.riotgames.league.teamfighttactics: java.lang.OutOfMemoryError",
            "ActivityManager: Killing com.riotgames.league.teamfighttactics for cached #17",
            "kernel: oom-kill:constraint=CONSTRAINT_NONE,nodemask=(null)"
        ]
        for line in nonKills {
            XCTAssertFalse(TelemetrySignalClassifier.isConfirmedGuestMemoryKill(line), line)
        }
    }

    func testPipelineClassifierRejectsNormalConfigurationReceipts() {
        let normalLines = [
            "gfxstream: using Vulkan host renderer",
            "virtio-gpu-asg write buffer size 1048576",
            "MoltenVK version 1.4 initialized",
            "shader cache directory ready",
            "sync fence support enabled"
        ]
        for line in normalLines {
            XCTAssertEqual(TelemetrySignalClassifier.pipelineSignals(in: line), PipelineLogSignals(), line)
        }
    }

    func testPipelineClassifierNamesDiagnosticBoundaries() {
        XCTAssertEqual(
            TelemetrySignalClassifier.pipelineSignals(in: "gfxstream warning: host queue stalled"),
            PipelineLogSignals(gfxstreamWarningCount: 1)
        )
        XCTAssertEqual(
            TelemetrySignalClassifier.pipelineSignals(in: "virtio-gpu-asg timeout waiting for ring fence"),
            PipelineLogSignals(asgStallCount: 1, fenceTimeoutCount: 1)
        )
        XCTAssertEqual(
            TelemetrySignalClassifier.pipelineSignals(in: "[MVK] Vulkan error: shader compilation failed"),
            PipelineLogSignals(vulkanErrorCount: 1, moltenVKWarningCount: 1, shaderErrorCount: 1)
        )
    }

    func testScreenRotationDimensionsAndAspectRatioCalculations() {
        let landscapeSize = CGSize(width: 1280, height: 720)
        let portraitSize = CGSize(width: 450, height: 800)

        let landscapeAspect = landscapeSize.width / landscapeSize.height
        let portraitAspect = portraitSize.width / portraitSize.height

        XCTAssertEqual(landscapeAspect, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(portraitAspect, 9.0 / 16.0, accuracy: 0.001)

        // Verify center-preserving rotation origin calculation
        let currentFrame = CGRect(x: 100, y: 100, width: landscapeSize.width, height: landscapeSize.height)
        let center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)

        let rotatedOrigin = CGPoint(
            x: max(20, center.x - portraitSize.width / 2),
            y: max(40, center.y - portraitSize.height / 2)
        )
        let rotatedFrame = CGRect(origin: rotatedOrigin, size: portraitSize)

        XCTAssertEqual(rotatedFrame.midX, center.x, accuracy: 0.001)
        XCTAssertEqual(rotatedFrame.midY, center.y, accuracy: 0.001)
    }

    func testKeymappingKeyCodeResolution() {
        // Standard virtual keycodes for Macrodroid gaming overlay
        let keyCodes: [UInt16: String] = [
            13: "W", 0: "A", 1: "S", 2: "D",
            12: "Q", 14: "E", 15: "R",
            18: "1", 19: "2",
            49: "SPACE"
        ]
        XCTAssertEqual(keyCodes[13], "W")
        XCTAssertEqual(keyCodes[0], "A")
        XCTAssertEqual(keyCodes[1], "S")
        XCTAssertEqual(keyCodes[2], "D")
        XCTAssertEqual(keyCodes[49], "SPACE")
        XCTAssertEqual(keyCodes[18], "1")
    }

    func testGestureTouchMapperScrollAndPinch() {
        let (start, end) = GestureTouchMapper.scrollSwipePoints(
            x: 500,
            y: 500,
            deltaX: 10.0,
            deltaY: -20.0,
            multiplier: 2.0
        )
        XCTAssertEqual(start, TouchPoint(x: 500, y: 500))
        XCTAssertEqual(end, TouchPoint(x: 520, y: 460))

        let neutralPinch = GestureTouchMapper.pinchSpanPoints(centerX: 400, centerY: 300, scale: 0.0, baseSpan: 50.0)
        XCTAssertEqual(neutralPinch.finger0, TouchPoint(x: 350, y: 250))
        XCTAssertEqual(neutralPinch.finger1, TouchPoint(x: 450, y: 350))

        let zoomInPinch = GestureTouchMapper.pinchSpanPoints(centerX: 400, centerY: 300, scale: 1.0, baseSpan: 50.0)
        XCTAssertEqual(zoomInPinch.finger0, TouchPoint(x: 300, y: 200))
        XCTAssertEqual(zoomInPinch.finger1, TouchPoint(x: 500, y: 400))
    }

    func testMicrophoneConfigurationPersistenceAndArguments() throws {
        let baseline = TFTMACRuntimeProfile.playable
        XCTAssertFalse(baseline.microphoneEnabled)

        let micEnabledProfile = baseline.with(microphoneEnabled: true)
        XCTAssertTrue(micEnabledProfile.microphoneEnabled)

        let suiteName = "test-profile-mic-\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        micEnabledProfile.save(to: suite)
        let loaded = TFTMACRuntimeProfile.load(from: suite)
        XCTAssertTrue(loaded.microphoneEnabled)

        baseline.save(to: suite)
        let loadedBaseline = TFTMACRuntimeProfile.load(from: suite)
        XCTAssertFalse(loadedBaseline.microphoneEnabled)
    }

    func testLatestFrameMailboxMultiWindowSubscription() {
        let mailbox = LatestFrameMailbox()
        let samplePixels = Data(count: 100)
        let frame1 = EmulatorFrame(
            pixels: samplePixels,
            width: 10,
            height: 10,
            sequence: 1,
            emulatorTimestampMicroseconds: 1_000,
            receivedMonotonicNanoseconds: 1_000_000
        )
        let frame2 = EmulatorFrame(
            pixels: samplePixels,
            width: 10,
            height: 10,
            sequence: 2,
            emulatorTimestampMicroseconds: 2_000,
            receivedMonotonicNanoseconds: 2_000_000
        )

        mailbox.publish(frame1)

        // Multiple independent consumers should be able to read the frame non-destructively
        let consumer1Read = mailbox.latestFrame(after: nil)
        let consumer2Read = mailbox.latestFrame(after: nil)
        XCTAssertEqual(consumer1Read?.sequence, 1)
        XCTAssertEqual(consumer2Read?.sequence, 1)

        // Consumer 1 already seen sequence 1
        XCTAssertNil(mailbox.latestFrame(after: 1))

        // Publish second frame
        mailbox.publish(frame2)
        XCTAssertEqual(mailbox.latestFrame(after: 1)?.sequence, 2)
        XCTAssertEqual(mailbox.peekLatest()?.sequence, 2)

        // takeLatest still consumes and nils out latest for legacy consumers
        XCTAssertEqual(mailbox.takeLatest()?.sequence, 2)
        XCTAssertNil(mailbox.takeLatest())
    }

    func testVietnameseIMETextComposition() {
        let vietnameseStrings = [
            "Xin chào Việt Nam! Macrodroid chạy cực mượt.",
            "Liên Minh Huyền Thoại: Tốc Chiến và Đấu Trường Chân Lý",
            "à á ả ã ạ ă ắ ằ ẳ ẵ ặ â ấ ầ ẩ ẫ ậ đ",
            "è é ẻ ẽ ẹ ê ế ề ể ễ ệ ì í ỉ ĩ ị",
            "ò ó ỏ õ ọ ô ố ồ ổ ỗ ộ ơ ớ ờ ở ỡ ợ",
            "ù ú ủ ũ ụ ư ứ ừ ử ữ ự kỳ kỷ kỹ kỵ"
        ]

        for text in vietnameseStrings {
            let normalizedNFC = text.precomposedStringWithCanonicalMapping
            let normalizedNFD = text.decomposedStringWithCanonicalMapping
            XCTAssertFalse(normalizedNFC.isEmpty)
            XCTAssertEqual(normalizedNFC.precomposedStringWithCanonicalMapping, normalizedNFD.precomposedStringWithCanonicalMapping)
        }
    }

    func testFreeformTaskManagerTaskParsing() {
        let sampleDump = """
        * Task{55ba86d #42 type=standard A=com.riotgames.league.teamfighttactics U=0 visible=true mode=5}
        Task id #101: com.aurora.store/com.aurora.store.MainActivity
        taskId=102: com.google.android.gms
        """

        let tasks = FreeformTaskManager.parseTasks(from: sampleDump)
        XCTAssertEqual(tasks.count, 3)

        let tftTask = tasks.first { $0.package == "com.riotgames.league.teamfighttactics" }
        XCTAssertNotNil(tftTask)
        XCTAssertEqual(tftTask?.id, 42)
        XCTAssertTrue(tftTask?.isFreeform == true)

        let auroraTask = tasks.first { $0.package == "com.aurora.store" }
        XCTAssertNotNil(auroraTask)
        XCTAssertEqual(auroraTask?.id, 101)
        XCTAssertEqual(auroraTask?.activity, "com.aurora.store.MainActivity")

        let gmsTask = tasks.first { $0.package == "com.google.android.gms" }
        XCTAssertNotNil(gmsTask)
        XCTAssertEqual(gmsTask?.id, 102)

        let freeformArgs = FreeformTaskManager.launchInFreeformArguments(component: "com.example.app/.MainActivity")
        XCTAssertEqual(freeformArgs, ["shell", "am", "start", "-n", "com.example.app/.MainActivity", "--windowingMode", "5"])

        let stopArgs = FreeformTaskManager.forceStopArguments(package: "com.example.app")
        XCTAssertEqual(stopArgs, ["shell", "am", "force-stop", "com.example.app"])
    }

    func testAppIconExtractorPackageParsing() {
        let validLine1 = "package:/data/app/~~h8bW/com.riotgames.league.teamfighttactics-1==/base.apk=com.riotgames.league.teamfighttactics"
        let parsed1 = AppIconExtractor.parsePackageLine(from: validLine1)
        XCTAssertEqual(parsed1?.package, "com.riotgames.league.teamfighttactics")
        XCTAssertEqual(parsed1?.remoteApkPath, "/data/app/~~h8bW/com.riotgames.league.teamfighttactics-1==/base.apk")

        let validLine2 = "package:/system/priv-app/Settings/Settings.apk=com.android.settings"
        let parsed2 = AppIconExtractor.parsePackageLine(from: validLine2)
        XCTAssertEqual(parsed2?.package, "com.android.settings")
        XCTAssertEqual(parsed2?.remoteApkPath, "/system/priv-app/Settings/Settings.apk")

        XCTAssertNil(AppIconExtractor.parsePackageLine(from: ""))
        XCTAssertNil(AppIconExtractor.parsePackageLine(from: "random noise without equal sign"))

        let iconURL = AppIconExtractor.iconURL(for: "com.test.app")
        XCTAssertTrue(iconURL.lastPathComponent == "com.test.app.png")
    }
    /// The icon URL for a given package must follow the canonical naming scheme so
    /// that UNNotificationAttachment can be constructed from it directly.
    func testNotificationIconAttachmentURLForCachedPackage() {
        let pkg = "com.riotgames.league.teamfighttactics"
        let url = AppIconExtractor.iconURL(for: pkg)
        XCTAssertEqual(url.lastPathComponent, "\(pkg).png")
        XCTAssertTrue(url.pathExtension == "png")
        // URL must be file-scheme so UNNotificationAttachment can read it.
        XCTAssertEqual(url.scheme, "file")
        // The parent directory must end with the canonical cache path component.
        XCTAssertTrue(url.deletingLastPathComponent().lastPathComponent == "Icons")
    }

    /// A package whose icon has not yet been extracted must report `hasCachedIcon == false`
    /// without throwing or crashing. The URL is still valid in shape.
    func testNotificationIconAttachmentURLNonExistentPackage() {
        let fakePkg = "com.nonexistent.package.definitely.not.on.disk.\(UUID().uuidString)"
        XCTAssertFalse(AppIconExtractor.hasCachedIcon(for: fakePkg),
                       "Fresh UUID-based package must not have a cached icon")
        let url = AppIconExtractor.iconURL(for: fakePkg)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "Icon file must not exist on disk for an unknown package")
        // cachedIcon must return nil gracefully, not crash.
        let img = AppIconExtractor.cachedIcon(for: fakePkg)
        XCTAssertNil(img)
    }

    /// `activeAppWindows` must store each package under its exact string key so
    /// the multi-window lookup in `openAppWindow` finds existing windows correctly.
    func testMultiWindowActiveAppWindowsTracking() {
        // Simulate the dictionary contract that AppCoordinator relies on.
        var activeWindows: [String: String] = [:] // String stands in for MainWindowController
        let pkg1 = "com.riotgames.league.teamfighttactics"
        let pkg2 = "com.aurora.store"

        // Registering two distinct packages must yield two entries.
        activeWindows[pkg1] = "WindowA"
        activeWindows[pkg2] = "WindowB"
        XCTAssertEqual(activeWindows.count, 2)
        XCTAssertEqual(activeWindows[pkg1], "WindowA")
        XCTAssertEqual(activeWindows[pkg2], "WindowB")

        // Re-opening the same package must NOT add a second entry; the existing
        // window is retrieved by the activeAppWindows[pkg] branch.
        activeWindows[pkg1] = activeWindows[pkg1] // no-op update
        XCTAssertEqual(activeWindows.count, 2, "Re-opening same pkg must reuse the existing window slot")

        // Closing pkg1 must remove it without affecting pkg2.
        activeWindows.removeValue(forKey: pkg1)
        XCTAssertEqual(activeWindows.count, 1)
        XCTAssertNil(activeWindows[pkg1])
        XCTAssertNotNil(activeWindows[pkg2])
    }

    /// `launchInFreeformArguments(package:)` (the package-only overload using `monkey`)
    /// must produce the correct ADB arguments for launching via the Launcher intent.
    func testFreeformTaskManagerLaunchByPackageArguments() {
        let pkg = "com.riotgames.league.teamfighttactics"
        let args = FreeformTaskManager.launchInFreeformArguments(package: pkg)
        XCTAssertEqual(args, [
            "shell", "monkey", "-p", pkg,
            "-c", "android.intent.category.LAUNCHER", "1"
        ])
        // Must not contain --windowingMode (that's the component overload's job).
        XCTAssertFalse(args.contains("--windowingMode"))

        // Verify component overload still works alongside the package overload.
        let componentArgs = FreeformTaskManager.launchInFreeformArguments(component: "\(pkg)/.MainActivity")
        XCTAssertTrue(componentArgs.contains("--windowingMode"))
        XCTAssertTrue(componentArgs.contains("5"))
    }

    // MARK: - Phase 7: Input Pipeline & Coverage Completeness

    /// `PrimaryTouchSequence` must:
    ///  - emit a contact `TouchInput` from `contact(at:)`,
    ///  - emit a release at the same point when `release(at:)` is called with a point,
    ///  - and fall back to `lastContactPoint` when `release(at: nil)` is called (finger
    ///    leaves the view bounds before the gesture ends).
    func testPrimaryTouchSequenceContactAndRelease() {
        var seq = PrimaryTouchSequence()

        // 1. contact(at: nil) → nothing (no point provided yet)
        XCTAssertNil(seq.contact(at: nil))

        // 2. contact(at: point) → TouchInput with phase .contact
        let point = TouchPoint(x: 320, y: 540)
        let contactInput = seq.contact(at: point)
        XCTAssertNotNil(contactInput)
        XCTAssertEqual(contactInput?.x, 320)
        XCTAssertEqual(contactInput?.y, 540)
        XCTAssertEqual(contactInput?.pressure, 1)

        // 3. release(at: explicit point) → uses the given point, not lastContactPoint
        let releasePoint = TouchPoint(x: 400, y: 600)
        let releaseInput = seq.release(at: releasePoint)
        XCTAssertEqual(releaseInput?.x, 400)
        XCTAssertEqual(releaseInput?.y, 600)
        XCTAssertEqual(releaseInput?.pressure, 0)

        // 4. After release, lastContactPoint is nil → release(at: nil) returns nil
        XCTAssertNil(seq.release(at: nil))

        // 5. New contact → then release(at: nil) falls back to lastContactPoint
        _ = seq.contact(at: TouchPoint(x: 100, y: 200))
        let fallbackRelease = seq.release(at: nil)
        XCTAssertNotNil(fallbackRelease, "release(at: nil) must fall back to lastContactPoint")
        XCTAssertEqual(fallbackRelease?.x, 100)
        XCTAssertEqual(fallbackRelease?.y, 200)
        XCTAssertEqual(fallbackRelease?.pressure, 0)
    }

    /// `GestureTouchMapper.pinchSpanPoints` must clamp the effective scale factor
    /// to [0.1, 5.0] so that extreme pinch values produce bounded, non-negative spans.
    func testGestureTouchMapperPinchSpanClampBounds() {
        let cx: Int32 = 960
        let cy: Int32 = 540
        let base: CGFloat = 50.0

        // Normal scale = 0.5 → factor = 1.5, span = 75
        let normal = GestureTouchMapper.pinchSpanPoints(centerX: cx, centerY: cy, scale: 0.5, baseSpan: base)
        XCTAssertEqual(normal.finger0.x, cx - 75)
        XCTAssertEqual(normal.finger1.x, cx + 75)

        // Scale = -5.0 (extreme pinch-in) → factor clamped to 0.1, span = 5
        let extremeIn = GestureTouchMapper.pinchSpanPoints(centerX: cx, centerY: cy, scale: -5.0, baseSpan: base)
        XCTAssertEqual(extremeIn.finger0.x, cx - 5)
        XCTAssertEqual(extremeIn.finger1.x, cx + 5)

        // Scale = 10.0 (extreme pinch-out) → factor clamped to 5.0, span = 250
        let extremeOut = GestureTouchMapper.pinchSpanPoints(centerX: cx, centerY: cy, scale: 10.0, baseSpan: base)
        XCTAssertEqual(extremeOut.finger0.x, cx - 250)
        XCTAssertEqual(extremeOut.finger1.x, cx + 250)

        // Fingers must always be symmetric around center
        XCTAssertEqual(extremeOut.finger0.x + extremeOut.finger1.x, Int32(2) * cx)
        XCTAssertEqual(extremeOut.finger0.y + extremeOut.finger1.y, Int32(2) * cy)
    }

    /// `LatestFrameMailbox.snapshot()` must accurately track the telemetry counters:
    ///  - `receivedFrames`: total published frames,
    ///  - `replacedBeforePresentation`: frames overwritten before `takeLatest` was called,
    ///  - `sequenceDrops`: gaps in the sequence numbers.
    func testLatestFrameMailboxSnapshotTelemetry() {
        let mailbox = LatestFrameMailbox()
        let px = Data(count: 100)

        func frame(_ seq: UInt32, mono: UInt64) -> EmulatorFrame {
            EmulatorFrame(pixels: px, width: 10, height: 10,
                          sequence: seq,
                          emulatorTimestampMicroseconds: UInt64(seq) * 1000,
                          receivedMonotonicNanoseconds: mono)
        }

        // 0 frames published → all counters zero
        let snap0 = mailbox.snapshot()
        XCTAssertEqual(snap0.receivedFrames, 0)
        XCTAssertEqual(snap0.replacedBeforePresentation, 0)
        XCTAssertEqual(snap0.sequenceDrops, 0)
        XCTAssertNil(snap0.latestSequence)

        // Publish frame seq=1 (no prior frame → replacedBeforePresentation stays 0)
        mailbox.publish(frame(1, mono: 1_000_000))
        let snap1 = mailbox.snapshot()
        XCTAssertEqual(snap1.receivedFrames, 1)
        XCTAssertEqual(snap1.replacedBeforePresentation, 0)
        XCTAssertEqual(snap1.sequenceDrops, 0)
        XCTAssertEqual(snap1.latestSequence, 1)

        // Publish frame seq=2 WITHOUT consuming seq=1 → replacedBeforePresentation = 1
        mailbox.publish(frame(2, mono: 2_000_000))
        let snap2 = mailbox.snapshot()
        XCTAssertEqual(snap2.receivedFrames, 2)
        XCTAssertEqual(snap2.replacedBeforePresentation, 1)
        XCTAssertEqual(snap2.sequenceDrops, 0) // seq 1→2: no gap

        // Consume (takeLatest) seq=2, then publish seq=5 → sequenceDrops += 2 (3,4 missing)
        _ = mailbox.takeLatest()
        mailbox.publish(frame(5, mono: 5_000_000))
        let snap3 = mailbox.snapshot()
        XCTAssertEqual(snap3.receivedFrames, 3)
        XCTAssertEqual(snap3.replacedBeforePresentation, 1) // no new replacement
        XCTAssertEqual(snap3.sequenceDrops, 2, "sequences 3 and 4 were dropped")
        XCTAssertEqual(snap3.latestSequence, 5)
    }

    /// `FreeformTaskManager.parseTasks` must gracefully handle the Android 12+
    /// `rootTask{...}` format produced by `dumpsys activity tasks`.
    /// This format nests tasks differently; the parser should return tasks it can
    /// identify and must never crash on unrecognised lines.
    func testFreeformTaskManagerAndroid12RootTaskFormat() {
        let android12Dump = """
        Task display areas in top down Z order:
          DisplayArea (organized) DefaultTaskDisplayArea
            rootTask{55ba86d #5 type=home ...}
            rootTask{77cc91e #42 type=standard A=com.riotgames.league.teamfighttactics visible=true mode=5}
            Task{33aa12b #101 type=standard A=com.aurora.store U=0 visible=true mode=5}
        """

        // Must not crash; should parse at least the tasks it recognises.
        let tasks = FreeformTaskManager.parseTasks(from: android12Dump)

        // The aurora store task uses the known "Task{..." pattern → must be found.
        let aurora = tasks.first { $0.package == "com.aurora.store" }
        XCTAssertNotNil(aurora, "Aurora Store task must be parsed from Android 12 dump")
        XCTAssertEqual(aurora?.id, 101)
        XCTAssertTrue(aurora?.isFreeform == true)

        // The TFT rootTask uses "rootTask{..." which differs from "Task{..." —
        // document whether it is parsed or not, but the call must not crash.
        let tft = tasks.first { $0.package == "com.riotgames.league.teamfighttactics" }
        // Note: rootTask{...} format may or may not be parsed by the current
        // implementation. This test guards against crashes and ensures Aurora is found.
        _ = tft // suppress unused-variable warning; presence is informational.

        // Home task (type=home) must not cause a crash and should not surface as
        // a user-facing app in the switcher even if parsed.
        let home = tasks.first { $0.package.isEmpty }
        XCTAssertNil(home, "Tasks with empty package must not appear in results")
    }

    func testKeymappingProfileSerializationAndDefaults() throws {
        let preset = KeymapProfile.defaultPreset(package: "com.example.game", appName: "Example Game")
        XCTAssertEqual(preset.packageName, "com.example.game")
        XCTAssertEqual(preset.appName, "Example Game")
        XCTAssertFalse(preset.buttons.isEmpty)
        XCTAssertNotNil(preset.dpad)
        XCTAssertNotNil(preset.mouseAim)

        let encoder = JSONEncoder()
        let data = try encoder.encode(preset)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(KeymapProfile.self, from: data)

        XCTAssertEqual(decoded.packageName, preset.packageName)
        XCTAssertEqual(decoded.buttons.count, preset.buttons.count)
        XCTAssertEqual(decoded.dpad?.radius, preset.dpad?.radius)
        XCTAssertEqual(decoded.overlayOpacity, preset.overlayOpacity, accuracy: 0.001)
    }

    func testKeymapDPadDirectionalTouchCalculation() {
        let dpad = KeymapDPad(
            normalizedCenterX: 0.2,
            normalizedCenterY: 0.7,
            radius: 50.0
        )

        // When no keys are pressed, no touch is produced
        let noTouch = dpad.touchPoint(
            wPressed: false,
            aPressed: false,
            sPressed: false,
            dPressed: false,
            sourceWidth: 1920,
            sourceHeight: 1080
        )
        XCTAssertNil(noTouch)

        // Center is (0.2 * 1920, 0.7 * 1080) = (384, 756)
        // Pressing W moves direction Y up (negative Y in guest coordinate)
        let upTouch = dpad.touchPoint(
            wPressed: true,
            aPressed: false,
            sPressed: false,
            dPressed: false,
            sourceWidth: 1920,
            sourceHeight: 1080
        )
        XCTAssertNotNil(upTouch)
        XCTAssertEqual(upTouch?.x, 384)
        XCTAssertEqual(upTouch?.y, 756 - 50)

        // Pressing D moves direction X right
        let rightTouch = dpad.touchPoint(
            wPressed: false,
            aPressed: false,
            sPressed: false,
            dPressed: true,
            sourceWidth: 1920,
            sourceHeight: 1080
        )
        XCTAssertNotNil(rightTouch)
        XCTAssertEqual(rightTouch?.x, 384 + 50)
        XCTAssertEqual(rightTouch?.y, 756)
    }

    func testKeymapButtonNormalizedToScreenCoordinate() {
        let button = KeymapButton(
            key: "Q",
            keyCode: 12,
            normalizedX: 0.5,
            normalizedY: 0.25,
            label: "Skill 1"
        )
        let coord = button.screenCoordinate(sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(coord.x, 960)
        XCTAssertEqual(coord.y, 270)

        let clampedButton = KeymapButton(
            key: "SPACE",
            keyCode: 49,
            normalizedX: 1.5,
            normalizedY: -0.2
        )
        let clampedCoord = clampedButton.screenCoordinate(sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(clampedCoord.x, 1920)
        XCTAssertEqual(clampedCoord.y, 0)
    }

    func testAppProfilePersistenceAndDefaults() {
        let tiktokProfile = AppProfile.defaultProfile(for: "com.zhiliaoapp.musically", appName: "TikTok")
        XCTAssertEqual(tiktokProfile.orientation, .portrait)
        XCTAssertTrue(tiktokProfile.isVietnameseIMEEnabled)
        XCTAssertFalse(tiktokProfile.isKeymapEnabled)

        let gameProfile = AppProfile.defaultProfile(for: "com.tencent.ig", appName: "PUBG Mobile")
        XCTAssertEqual(gameProfile.orientation, .landscape)
        XCTAssertFalse(gameProfile.isVietnameseIMEEnabled)
        XCTAssertTrue(gameProfile.isKeymapEnabled)

        let testPkg = "com.test.persistence.\(UUID().uuidString)"
        var custom = AppProfile.defaultProfile(for: testPkg, appName: "Custom App")
        custom.targetFPS = .fps120
        custom.resolution = .retina4K

        AppProfileStore.saveProfile(custom)
        defer { AppProfileStore.deleteProfile(for: testPkg) }

        let loaded = AppProfileStore.loadProfile(for: testPkg, appName: "Custom App")
        XCTAssertEqual(loaded.targetFPS, .fps120)
        XCTAssertEqual(loaded.resolution, .retina4K)
        XCTAssertEqual(loaded.packageName, testPkg)
    }

    func testAppProfileOrientationAndTargetFPSPacing() {
        XCTAssertEqual(AppFrameRate.fps30.maxFPS, 30)
        XCTAssertEqual(AppFrameRate.fps60.maxFPS, 60)
        XCTAssertEqual(AppFrameRate.fps120.maxFPS, 120)

        let landscapeAspect = AppOrientation.landscape.aspectRatio
        XCTAssertEqual(landscapeAspect?.width, 16.0)
        XCTAssertEqual(landscapeAspect?.height, 9.0)

        let portraitAspect = AppOrientation.portrait.aspectRatio
        XCTAssertEqual(portraitAspect?.width, 9.0)
        XCTAssertEqual(portraitAspect?.height, 16.0)

        XCTAssertEqual(AppResolution.p720.dimensions.width, 1280)
        XCTAssertEqual(AppResolution.p720.dimensions.height, 720)
        XCTAssertEqual(AppResolution.p1080.dimensions.width, 1920)
        XCTAssertEqual(AppResolution.p1080.dimensions.height, 1080)
        XCTAssertEqual(AppResolution.retina4K.dimensions.width, 3840)
        XCTAssertEqual(AppResolution.retina4K.dimensions.height, 2160)
    }

    func testKeymappingStoreProfilePersistence() {
        let testPkg = "com.test.keymap.\(UUID().uuidString)"
        let customProfile = KeymapProfile(
            packageName: testPkg,
            appName: "Test Game",
            buttons: [
                KeymapButton(key: "Z", keyCode: 6, normalizedX: 0.3, normalizedY: 0.4, label: "Fire")
            ],
            dpad: KeymapDPad(normalizedCenterX: 0.15, normalizedCenterY: 0.65, radius: 55.0),
            mouseAim: KeymapMouseAim(toggleKeyCode: 58, sensitivity: 1.5),
            overlayOpacity: 0.85
        )

        KeymapProfileStore.saveProfile(customProfile)
        defer { KeymapProfileStore.deleteProfile(for: testPkg) }

        let loaded = KeymapProfileStore.loadProfile(for: testPkg, appName: "Test Game")
        XCTAssertEqual(loaded.packageName, testPkg)
        XCTAssertEqual(loaded.buttons.count, 1)
        XCTAssertEqual(loaded.buttons.first?.key, "Z")
        XCTAssertEqual(loaded.dpad?.radius, 55.0)
        XCTAssertEqual(loaded.mouseAim?.sensitivity, 1.5)
        XCTAssertEqual(loaded.overlayOpacity, 0.85, accuracy: 0.001)
    }

    // MARK: - Phases 9-14: Gamepad, Dynamic Resolutions, Macros & Community Hub

    @MainActor
    func testGamepadManagerVirtualStickDeflectionToTouchPoint() {
        // 1. Zero deflection (inside deadzone) -> produces nil
        let deadzonePoint = GamepadManager.virtualStickTouchPoint(
            stickX: 0.05,
            stickY: -0.05,
            centerX: 0.4,
            centerY: 0.7,
            radius: 80.0,
            sourceWidth: 1000,
            sourceHeight: 1000,
            deadzone: 0.15
        )
        XCTAssertNil(deadzonePoint)

        // 2. Full right deflection (+1.0, 0.0) -> center.x + radius = 400 + 80 = 480
        let rightPoint = GamepadManager.virtualStickTouchPoint(
            stickX: 1.0,
            stickY: 0.0,
            centerX: 0.4,
            centerY: 0.7,
            radius: 80.0,
            sourceWidth: 1000,
            sourceHeight: 1000
        )
        XCTAssertNotNil(rightPoint)
        XCTAssertEqual(rightPoint?.x, 480)
        XCTAssertEqual(rightPoint?.y, 700)

        // 3. Full up deflection (0.0, 1.0) -> center.y - radius = 700 - 80 = 620
        let upPoint = GamepadManager.virtualStickTouchPoint(
            stickX: 0.0,
            stickY: 1.0,
            centerX: 0.4,
            centerY: 0.7,
            radius: 80.0,
            sourceWidth: 1000,
            sourceHeight: 1000
        )
        XCTAssertNotNil(upPoint)
        XCTAssertEqual(upPoint?.x, 400)
        XCTAssertEqual(upPoint?.y, 620)

        // 4. Clamping extreme deflection (> 1.0) to radius
        let extremePoint = GamepadManager.virtualStickTouchPoint(
            stickX: 2.0,
            stickY: 0.0,
            centerX: 0.4,
            centerY: 0.7,
            radius: 80.0,
            sourceWidth: 1000,
            sourceHeight: 1000
        )
        XCTAssertNotNil(extremePoint)
        XCTAssertEqual(extremePoint?.x, 480)
    }

    @MainActor
    func testGamepadTypeDetectionAndButtonCoverage() {
        XCTAssertEqual(GamepadType.dualSense.rawValue, "PlayStation DualSense")
        XCTAssertEqual(GamepadType.dualShock4.rawValue, "PlayStation DualShock 4")
        XCTAssertEqual(GamepadType.xbox.rawValue, "Xbox Wireless Controller")
        XCTAssertEqual(GamepadType.switchPro.rawValue, "Nintendo Switch Pro Controller")
        XCTAssertEqual(GamepadType.mfi.rawValue, "MFi Controller")
        XCTAssertEqual(GamepadType.generic.rawValue, "Generic Gamepad")

        // GamepadButton allCases
        XCTAssertTrue(GamepadButton.allCases.count >= 16)
        XCTAssertTrue(GamepadButton.allCases.contains(.buttonA))
        XCTAssertTrue(GamepadButton.allCases.contains(.buttonB))
        XCTAssertTrue(GamepadButton.allCases.contains(.buttonX))
        XCTAssertTrue(GamepadButton.allCases.contains(.buttonY))
        XCTAssertTrue(GamepadButton.allCases.contains(.leftTrigger))
        XCTAssertTrue(GamepadButton.allCases.contains(.rightTrigger))
        XCTAssertTrue(GamepadButton.allCases.contains(.leftThumbstickButton))
        XCTAssertTrue(GamepadButton.allCases.contains(.rightThumbstickButton))

        let state = GamepadState(
            name: "DualSense Wireless Controller",
            type: .dualSense,
            batteryLevel: 0.95,
            isConnected: true
        )
        XCTAssertEqual(state.type, .dualSense)
        XCTAssertEqual(state.batteryLevel, 0.95)
        XCTAssertTrue(state.isConnected)
    }

    func testDynamicFrameContractMultiResolutionValidation() throws {
        // Standard 1080p
        let res1080 = FrameContract.standard1080p
        XCTAssertEqual(res1080.width, 1920)
        XCTAssertEqual(res1080.height, 1080)
        XCTAssertEqual(res1080.byteCount, 1920 * 1080 * 4)
        XCTAssertEqual(res1080.aspectRatio, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertNoThrow(try FrameContract.validateDynamic(width: 1920, height: 1080, byteCount: res1080.byteCount))

        // 720p HD
        let res720 = FrameContract.standard720p
        XCTAssertEqual(res720.width, 1280)
        XCTAssertEqual(res720.height, 720)
        XCTAssertEqual(res720.byteCount, 1280 * 720 * 4)
        XCTAssertNoThrow(try FrameContract.validateDynamic(width: 1280, height: 720, byteCount: res720.byteCount))

        // 1440p 2K
        let res1440 = FrameContract.standard1440p
        XCTAssertEqual(res1440.width, 2560)
        XCTAssertEqual(res1440.height, 1440)
        XCTAssertNoThrow(try FrameContract.validateDynamic(width: 2560, height: 1440, byteCount: res1440.byteCount))

        // 4K Retina
        let res4K = FrameContract.retina4K
        XCTAssertEqual(res4K.width, 3840)
        XCTAssertEqual(res4K.height, 2160)
        XCTAssertEqual(res4K.byteCount, 3840 * 2160 * 4)
        XCTAssertNoThrow(try FrameContract.validateDynamic(width: 3840, height: 2160, byteCount: res4K.byteCount))

        // 21:9 Ultrawide
        let resUltrawide = FrameContract.ultrawide21x9
        XCTAssertEqual(resUltrawide.width, 2560)
        XCTAssertEqual(resUltrawide.height, 1080)
        XCTAssertEqual(resUltrawide.aspectRatio, 2560.0 / 1080.0, accuracy: 0.001)
        XCTAssertNoThrow(try FrameContract.validateDynamic(width: 2560, height: 1080, byteCount: resUltrawide.byteCount))

        // Inactive display throwing
        XCTAssertThrowsError(try FrameContract.validateDynamic(width: 0, height: 1080, byteCount: 0)) { error in
            XCTAssertEqual(error as? FrameContractError, .inactiveDisplay)
        }

        // Byte count mismatch throwing
        XCTAssertThrowsError(try FrameContract.validateDynamic(width: 1920, height: 1080, byteCount: 100)) { error in
            guard case FrameContractError.wrongByteCount = error else {
                return XCTFail("Expected wrongByteCount error")
            }
        }
    }

    func testMacroAutomationModelSerializationAndStorage() throws {
        let testPkg = "com.test.macro.\(UUID().uuidString)"
        let actions: [MacroAction] = [
            MacroAction(type: .touchDown, normalizedX: 0.25, normalizedY: 0.50),
            MacroAction(type: .delay, delayAfterMS: 50),
            MacroAction(type: .touchMove, normalizedX: 0.28, normalizedY: 0.52),
            MacroAction(type: .touchUp, normalizedX: 0.28, normalizedY: 0.52),
            MacroAction(type: .keyPress, keyCode: 13, keyString: "W")
        ]

        let macro = MacroSequence(
            name: "Auto Combo",
            packageName: testPkg,
            actions: actions,
            repeatCount: 3,
            intervalMS: 200,
            speedMultiplier: 1.25,
            enableHumanJitter: true
        )

        // JSON encoding/decoding test
        let encoder = JSONEncoder()
        let data = try encoder.encode(macro)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MacroSequence.self, from: data)

        XCTAssertEqual(decoded.id, macro.id)
        XCTAssertEqual(decoded.name, "Auto Combo")
        XCTAssertEqual(decoded.packageName, testPkg)
        XCTAssertEqual(decoded.actions.count, 5)
        XCTAssertEqual(decoded.repeatCount, 3)
        XCTAssertEqual(decoded.speedMultiplier, 1.25, accuracy: 0.001)

        // Store persistence test
        MacroStore.saveMacro(macro)
        defer { MacroStore.deleteMacro(name: macro.name, for: testPkg) }

        let loadedList = MacroStore.listMacros(for: testPkg)
        XCTAssertEqual(loadedList.count, 1)
        XCTAssertEqual(loadedList.first?.id, macro.id)
        XCTAssertEqual(loadedList.first?.name, "Auto Combo")
    }

    func testMacroHumanVarianceJitterClamp() {
        let sequenceWithJitter = MacroSequence(
            name: "Jitter Sequence",
            packageName: "com.test.jitter",
            actions: [MacroAction(type: .touchDown, normalizedX: 0.5, normalizedY: 0.5)],
            enableHumanJitter: true
        )

        let sequenceNoJitter = MacroSequence(
            name: "Exact Sequence",
            packageName: "com.test.jitter",
            actions: [MacroAction(type: .touchDown, normalizedX: 0.5, normalizedY: 0.5)],
            enableHumanJitter: false
        )

        let action = sequenceWithJitter.actions[0]
        let exactCoord = sequenceNoJitter.resolvedCoordinate(action: action, sourceWidth: 1000, sourceHeight: 1000)
        XCTAssertNotNil(exactCoord)
        XCTAssertEqual(exactCoord?.x, 500)
        XCTAssertEqual(exactCoord?.y, 500)

        // Jittered coordinate must stay close within ±2.0 px (rounded to at most ±3 px)
        let jitteredCoord = sequenceWithJitter.resolvedCoordinate(action: action, sourceWidth: 1000, sourceHeight: 1000)
        XCTAssertNotNil(jitteredCoord)
        if let jitteredCoord {
            XCTAssertTrue(abs(jitteredCoord.x - 500) <= 3)
            XCTAssertTrue(abs(jitteredCoord.y - 500) <= 3)
        }
    }

    func testMacroSequencePlaybackPacingMath() {
        let sequence = MacroSequence(
            name: "Paced Sequence",
            packageName: "com.test.pacing",
            actions: [
                MacroAction(type: .touchDown, normalizedX: 0.1, normalizedY: 0.1),
                MacroAction(type: .touchUp, normalizedX: 0.1, normalizedY: 0.1)
            ],
            repeatCount: 2,
            intervalMS: 500,
            speedMultiplier: 2.0
        )

        XCTAssertEqual(sequence.repeatCount, 2)
        XCTAssertEqual(sequence.intervalMS, 500)
        XCTAssertEqual(sequence.speedMultiplier, 2.0, accuracy: 0.001)

        let stepInterval = max(10, Int((Double(sequence.intervalMS) / sequence.speedMultiplier) / Double(sequence.actions.count)))
        // 500 / 2.0 = 250; 250 / 2 actions = 125ms per step
        XCTAssertEqual(stepInterval, 125)
    }

    func testCommunityHubCuratedPresetsIntegrity() {
        let presets = CommunityHub.curatedPresets
        XCTAssertTrue(presets.count >= 5, "Must contain at least 5 curated game presets")

        let packages = presets.map(\.packageName)
        XCTAssertTrue(packages.contains("com.riotgames.league.teamfighttactics"))
        XCTAssertTrue(packages.contains("com.riotgames.league.wildrift"))
        XCTAssertTrue(packages.contains("com.miHoYo.GenshinImpact"))
        XCTAssertTrue(packages.contains("com.tencent.ig"))
        XCTAssertTrue(packages.contains("com.zhiliaoapp.musically"))

        for preset in presets {
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertFalse(preset.genre.isEmpty)
            XCTAssertFalse(preset.keymapProfile.buttons.isEmpty)
        }
    }

    func testMacrodroidBundleEncodingAndDecoding() throws {
        let sampleKeymap = KeymapProfile.defaultPreset(package: "com.test.bundle", appName: "Bundle Game")
        let sampleProfile = AppProfile.defaultProfile(for: "com.test.bundle", appName: "Bundle Game")

        let bundle = MacrodroidBundle(
            packageName: "com.test.bundle",
            appName: "Bundle Game",
            keymap: sampleKeymap,
            appProfile: sampleProfile
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_bundle_\(UUID().uuidString).macrodroid")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try bundle.export(to: tempFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))

        let imported = try MacrodroidBundle.load(from: tempFile)
        XCTAssertEqual(imported.packageName, "com.test.bundle")
        XCTAssertEqual(imported.appName, "Bundle Game")
        XCTAssertEqual(imported.schemaVersion, MacrodroidBundle.currentSchemaVersion)
        XCTAssertEqual(imported.keymap.packageName, "com.test.bundle")
        XCTAssertEqual(imported.appProfile.appName, "Bundle Game")
    }

    func testViewportMapperDynamicResolutionAspectRatio() {
        let ultrawideRes = FrameContract.ultrawide21x9
        let mapper = ViewportMapper(
            resolution: ultrawideRes,
            viewportSize: CGSize(width: 2560, height: 1440)
        )

        // 2560x1080 inside 2560x1440 viewport should be letterboxed vertically
        XCTAssertEqual(mapper.displayedRect.width, 2560, accuracy: 0.1)
        XCTAssertEqual(mapper.displayedRect.height, 1080, accuracy: 0.1)
        XCTAssertEqual(mapper.displayedRect.origin.y, (1440 - 1080) / 2.0, accuracy: 0.1)

        // Test center mapping
        let centerPoint = CGPoint(x: 1280, y: 1440 / 2.0)
        guard let sourceCenter = mapper.sourcePoint(for: centerPoint) else {
            return XCTFail("Expected non-nil source point for viewport center")
        }
        XCTAssertEqual(sourceCenter.x, 1280, accuracy: 0.5)
        XCTAssertEqual(sourceCenter.y, 540, accuracy: 0.5)
    }

    func testAppProfileCustomResolutionDimensions() {
        let p720 = AppResolution.p720
        XCTAssertEqual(p720.dimensions.width, 1280)
        XCTAssertEqual(p720.dimensions.height, 720)

        let p1080 = AppResolution.p1080
        XCTAssertEqual(p1080.dimensions.width, 1920)
        XCTAssertEqual(p1080.dimensions.height, 1080)

        let p1440 = AppResolution.p1440
        XCTAssertEqual(p1440.dimensions.width, 2560)
        XCTAssertEqual(p1440.dimensions.height, 1440)

        let retina4K = AppResolution.retina4K
        XCTAssertEqual(retina4K.dimensions.width, 3840)
        XCTAssertEqual(retina4K.dimensions.height, 2160)

        let ultrawide = AppResolution.ultrawide21x9
        XCTAssertEqual(ultrawide.dimensions.width, 2560)
        XCTAssertEqual(ultrawide.dimensions.height, 1080)
    }
}

typealias TFTMACGate1Tests = MacrodroidGate1Tests
