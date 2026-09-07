import CoreGraphics
import XCTest

final class TFTMACGate1Tests: XCTestCase {
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

        // Validate IdleSuspendTimeout and IdleSuspendPreferences
        XCTAssertEqual(IdleSuspendTimeout.allCases.count, 5)
        XCTAssertEqual(IdleSuspendTimeout.immediately.seconds, 0)
        XCTAssertEqual(IdleSuspendTimeout.oneMinute.seconds, 60)
        XCTAssertEqual(IdleSuspendTimeout.fiveMinutes.seconds, 300)
        XCTAssertEqual(IdleSuspendTimeout.fifteenMinutes.seconds, 900)
        XCTAssertNil(IdleSuspendTimeout.never.seconds)

        let idleDefaults = UserDefaults(suiteName: "test.idle.suspend")!
        idleDefaults.removeObject(forKey: IdleSuspendPreferences.preferenceKey)
        XCTAssertEqual(IdleSuspendPreferences.loadTimeout(defaults: idleDefaults), .fiveMinutes)
        IdleSuspendPreferences.saveTimeout(.immediately, defaults: idleDefaults)
        XCTAssertEqual(IdleSuspendPreferences.loadTimeout(defaults: idleDefaults), .immediately)
        IdleSuspendPreferences.saveTimeout(.never, defaults: idleDefaults)
        XCTAssertEqual(IdleSuspendPreferences.loadTimeout(defaults: idleDefaults), .never)
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
}
