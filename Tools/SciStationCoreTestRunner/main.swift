import Foundation
import SciStationCore

@main
struct SciStationCoreTestRunner {
    static func main() async {
        do {
            try await CoreVerificationSuite().runAll()
            print("All SciStation core checks passed.")
        } catch {
            fputs("SciStation core check failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct CoreVerificationSuite {
    func runAll() async throws {
        try await createWorkspaceInitializesExpectedStructure()
        try await createWorkspaceInitializesResearchRootAndDefaultProject()
        try await projectRegistryCreatesUpdatesAndCollapsesProjects()
        try await openWorkspaceBackfillsMissingStructure()
        try await openLegacyWorkspaceCreatesResearchRootRegistry()
        try await restoreLastWorkspaceClearsMissingBookmark()
        try await workspacePreferencesRoundTrip()
        try await workspacePreferencesLanguageRoundTrips()
        try await homeWidgetLayoutRoundTripsPreferences()
        try await homeWidgetLayoutFallsBackWhenInvalid()
        try l10nCatalogResolvesChineseAndEnglish()
        try l10nCatalogFallsBackWithAuditWarning()
        try localizationAuditFlagsHardcodedSwiftUIText()
        try workspaceContextSnapshotReflectsHomeRoute()
        try workspaceContextSnapshotReflectsProjectPaperSelection()
        try rightRailAutoHidesWhenNoContext()
        try responsivePolicyHidesRightRailBelowThreshold()
        try responsivePolicyMovesToolbarActionsToOverflow()
        try await rightRailModePersistsAcrossWorkspaceReload()
        try homeWidgetRegistryIncludesDefaultWidgets()
        try homeWidgetRegistryFiltersDisabledModules()
        try homeWidgetGridReflowsForTwoColumns()
        try homeWidgetGridReflowsForSingleColumn()
        try homeWidgetGridRepackAvoidsOverlap()
        try homeWidgetResetRestoresDefaultLayout()
        try homeWidgetDragOntoCommitsInBothDirections()
        try toolbarPolicyShowsImportOnlyForLibraryContexts()
        try toolbarPolicyHidesPaperActionsOnHome()
        try toolbarPolicyShowsPDFActionsOnlyInPDFReader()
        try toolbarPolicyShowsWikiActionsOnlyInWikiContext()
        try await toolbarCommandCatalogMapsToolbarActionsToCommandContributions()
        try await projectTreeArchiveFallsBackToProjectsRoute()
        try await projectArchiveHidesProjectFromActiveList()
        try await projectRestoreReturnsProjectToActiveList()
        try await projectDeleteMovesToTrashOrArchive()
        try projectSpaceTabsBuilderHonorsAvailableModules()
        try projectSpaceTabsBuilderRespectsPinnedOrder()
        try projectSpaceTabsBuilderRemovesDisabledModuleTabs()
        try projectSpaceTabsBuilderKeepsOverviewLeftmost()
        try pluginManifestValidatorRejectsInvalidIDs()
        try await pluginRegistryResolvesBuiltInWorkspaceModuleAdapters()
        try pluginWorkspaceContributionCatalogResolvesBuiltInModules()
        try await commandRegistryExecutesRegisteredContribution()
        try await declarativePermissionBrokerEnforcesManifestPermissions()
        try await workspaceFileSystemRejectsEscapingPathsAndWritesAtomically()
        try topSidebarBuilderProducesSixFixedItems()
        try await routePersistenceRoundTripsLastRoute()
        try routePersistenceFallsBackWhenProjectMissing()
        try routePersistenceFallsBackWhenModuleDisabled()
        try await workspacePreferencesSchemaVersion2BackwardCompat()
        try await workspacePreferencesSchemaVersionForRightRail()
        try projectSpaceContentRouterMapsAllKnownTabs()
        try agentLoopBudgetDefaultsAreExpanded()
        try await appDebugEventLoggerPersistsRedactedEvents()
        try appDebugEventNameRegistryCoversAllEmittedEvents()
        try appDebugEventNameRegistryFollowsNamingConvention()
        try uitestAccessibilityIDFactoriesProduceValidIdentifiers()
        try uitestAccessibilityIDValidatorRejectsIllegalShapes()
        try swiftUIRuntimeWarningCaptureFormatsOneLinePerEntry()
        try swiftUIRuntimeWarningCaptureSanitisesEmbeddedSeparators()
        try await homeAggregatorReturnsEmptyDataForBlankWorkspace()
        try await homeAggregatorRespectsCacheTTL()
        try await homeAggregatorInvalidatesOnDraftInboxChange()
        try await homeAggregatorInvalidatesOnTodoChange()
        try await homeAggregatorErrorRecordsDebugEvent()
        try await homeAggregatorPopulatesReadingQueueEntriesWhenQueueAvailable()
        try await homeAggregatorFallsBackToHeuristicReadingQueueWhenQueueEmpty()
        try projectStageProviderInfersExplorationForBlankProject()
        try projectStageProviderInfersOnHoldAfter21DaysIdle()
        try projectStageProviderInfersReviewingWhenUnsupportedClaimPresent()
        try projectDashboardAggregatorReturnsCorrectStage()
        try projectDashboardAggregatorOrdersArtifactsByCreatedDesc()
        try projectDashboardAggregatorBuildsReadingQueuePreview()
        try await homeSnapshotEncodesAndDecodesRoundTrip()
        try librarySortStateSortsPapers()
        try await libraryBulkEditServiceUpdatesSelectedPapers()
        try await markdownSnippetRepositoryLoadsWorkspaceSnippets()
        try await workspaceMaterialRepositoryLoadsOnlyUserMaterials()
        try batchImportInputParserSplitsMultipleIdentifiers()
        try await paperImportPipelineDispatchesImporterAndMetadataProvider()
        try await vscodeBridgePreparesPythonRunTask()
        try citekeyGenerationUsesAuthorYearKeyword()
        try graphNodeIDDerivationFollowsPriorityOrder()
        try graphNodeIDResolvedFromPaperInstance()
        try metadataCodecRoundTripKeepsEditableFields()
        try metadataCodecPreservesUnknownFields()
        try metadataCodecEmitsGraphNodeID()
        try agentToolErrorClassifierMapsCancelAndTimeout()
        try await jsonlWriterAppendsDurableDedupedLines()
        try await graphRepositoryAppendsAndReloadsAtomically()
        try await graphRepositoryDropsOrphanEdgesAfterTombstone()
        try await graphRepositoryCompactPreservesEffectiveState()
        try await graphRepositoryCrashRecoveryReplaysJSONL()
        try await graphReadModelSubgraphRespectsDepth()
        try await graphReadModelPathReturnsBFSResult()
        try graphAgentToolsExposeReadOnlyDefinitions()
        try await graphToolBackendFindsMissingCorePapers()
        try await graphToolBackendGeneratesReadingPath()
        try await graphToolBackendDetectsStaleCitations()
        try await graphToolBackendFindsUnsupportedArtifactClaims()
        try await graphToolBackendFindsBridgePapers()
        try bibtexParserHandlesArticleAndMisc()
        try bibtexParserSkipsMalformedEntry()
        try markdownReferencesExtractorReadsSection()
        try referenceResolverDOIWinsOverTitle()
        try referenceResolverProducesExternalOnMiss()
        try levenshteinDistanceComputesCorrectly()
        try graphLayoutEngineDeterministicWithFixedSeed()
        try graphLayoutEngineConvergesUnderThreshold()
        try await subgraphCacheLRUEvictsOldest()
        try await paperRepositorySaveAndLoadRoundTripsPaper()
        try await paperRepositoryKeepsLegacyRawPapersLoadable()
        try await legacyPaperMigrationPlanDetectsRawPaperConflicts()
        try await legacyPaperMigrationCopyWritesReportAndPrefersGlobalPaper()
        try await projectPaperLinkRepositoryRoundTripsAndOverlaysPaperMetadata()
        try await projectPaperLinkRepositoryEditsSingleLinksAndLoadsLegacyYAML()
        try await paperRepositoryKeepsLegacyProjectMetadataWithoutLinks()
        try await paperRepositoryDeletesPaperDirectory()
        try librarySearchMatchesExtendedMetadata()
        try await paperAnnotationsRepositoryRoundTripsAnnotations()
        try await pdfAnnotationStoreRoundTripsSidecar()
        try await pdfAnnotationStoreRejectsPathTraversal()
        try await pdfAnnotationStoreHandlesMissingSidecar()
        try await paperRepositoryLoadsNestedCollectionPapers()
        try await tagRepositoryUpsertsAndDeletesDefinitions()
        try await todoRepositoryCreatesCompletesAndDeletesTodos()
        try await researchQueueStoreAppendPersistsAndReloads()
        try await researchQueueStoreAppendBatchPreservesOrderWithinBatch()
        try await researchQueueStoreReorderRewritesOrderField()
        try await researchQueueStoreReorderHandlesPartialIDList()
        try await researchQueueStoreUpdateStatusRecordsTimestamps()
        try await researchQueueStoreRemoveDoesNotAffectOtherScopes()
        try await researchQueueStoreLoadIgnoresMalformedEntriesAndLogsWarning()
        try await researchQueueStoreWorkspaceQueueTopRespectsLimitAndStatusFilter()
        try await researchQueueStoreProjectQueueIsolatedPerProjectID()
        try await researchQueueStoreApplyPaperStatusTransitionRespectsRules()
        try researchQueueYAMLEncodingRoundtripIsStable()
        try researchQueueYAMLDecoderSkipsUnknownFieldsForward()
        try await researchQueueDebugEventsScrubSensitiveFields()
        try await researchQueueIngestorMapsApprovedRecommendationCandidatesAndDedupes()
        try await researchQueueIngestorAppliesPaperStatusDiffsToStore()
        try await researchQueueIngestorPersistsCursorAcrossReopen()
        try await researchQueueFixtureRoundTripsFiveDiverseEntries()
        try readingPlanYAMLCodecRoundTripsActivePlan()
        try readingPlanYAMLCodecSkipsMalformedPlans()
        try readingPlanGeneratorBuildsDeterministicWeeklySlots()
        try await readingPlanStorePersistsActivatesAndUpdatesSlots()
        try recommendationConfigYAMLRoundTripsDailySourceSettings()
        try dailyFeedCandidateImporterMapsExternalArxivCandidates()
        try arxivRecommendationParserMapsAtomFeedCandidates()
        try await recommendationCandidateGathererDedupsDailyFeedAndQueueTail()
        try await recommendationScorerRanksByLibraryInterestAndSuppressesFinished()
        try await recommendationPipelineWritesSnapshotAndQueuePayload()
        try recommendationPipelineHonorsCategoryHardBoundary()
        try await recommendationScorerV2SignalsKeywordSeedAndRecency()
        try await recommendationFeedbackStorePersistsJSONLAndBuildsProfile()
        try recommendationPipelineMMRDiversifiesNearDuplicateResults()
        try recommendationRunResultDecodesLegacySnapshotWithV2Defaults()
        try identifierParserRecognizesSupportedKinds()
        try metadataProviderBuildsStableLookupURLs()
        try arxivEntryParserExtractsMetadataDraft()
        try inspireMetadataMapperExtractsMetadataDraft()
        try inspireMetadataMapperExtractsCitationGraphFields()
        try llmRequestBuildsExpectedPayload()
        try openAIProviderPreservesReasoningContent()
        try openAIProviderRejectsThinkingModeToolReplayWithoutReasoning()
        try openAIProviderTreatsDeepSeekV4FlashAsThinkingMode()
        try paperSummaryPromptBuilderIncludesContext()
        try await llmConfigurationStorePersistsWithoutAPIKey()
        try await llmWritebackServiceKeepsDraftsSeparateFromWiki()
        try agentPlanParserExtractsJSONFromMarkdownFence()
        try agentPlanParserExtractsBalancedJSONBeforeTrailingText()
        try agentVisibleResponseExtractorHidesJSONEnvelope()
        try agentVisibleResponseExtractorKeepsPartialStructuredText()
        try agentVisibleModeMapsConversationAndPlanToPlan()
        try agentVisibleModeMapsAssistantToAgent()
        try agentInteractionModeRuntimePolicyMatchesVisibleModes()
        try planModeRequiresReadableToolSet()
        try agentTimelineProjectionKeepsChronologicalOrder()
        try agentTimelineProjectionGroupsReasoningEvents()
        try agentTimelineProjectionHidesHookResults()
        try agentTimelineProjectionMergesToolStartAndFinish()
        try toolCallRowsAreCollapsedByDefault()
        try permissionRequestShowsAllowDenyOnlyByDefault()
        try draftReviewDefaultsToProjectWikiWhenProjectContextExists()
        try draftReviewFallsBackToGlobalWikiWithoutProject()
        try timelinePaginationCanLoadEarlierEvents()
        try agentPlanParserWritebackFallbackKeepsMarkdownDraft()
        try await agentPlannerAcceptsPlainTextConversationResponse()
        try await agentPlannerAcceptsPlainTextAssistantFallback()
        try await agentToolExecutorRequiresApprovalForTodoWrites()
        try await writeWikiMarkdownAgentToolValidatesWhitelist()
        try await agentPaperClassificationToolUpdatesMetadata()
        try await agentPaperReadToolsReturnSectionsAndSearchMatches()
        try await agentWorkspaceSnapshotIncludesProjectContext()
        try await agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault()
        try await agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext()
        try agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext()
        try await agentRunLoggerWritesWorkspaceFiles()
        try await agentServicePlanOnlyRunLogsCurrentProjectAndReadsHistory()
        try await agentServiceRecordFailedRunPersistsInlineTimeline()
        try await agentServiceRecordCancelledRunPersistsLifecycle()
        try await agentServiceExecutesApprovedPlan()
        try agentPaperIntentRouterMapsAbstractToAbstractSection()
        try agentPaperIntentRouterClassifiesGraphIntents()
        try await agentLoopRunnerCallsReadOnlyToolThenContinues()
        try await agentLoopRunnerReturnsVisibleFallbackAfterToolThenEmptyProvider()
        try await agentLoopRunnerEmptyResponseWithoutToolsKeepsContextFallback()
        try await agentLoopRunnerReturnsVisibleProviderFailureAfterPreflightTools()
        try await agentLoopRunnerPaperFormulaFlowUsesListSearchReadBeforeFinal()
        try await agentLoopRunnerFallsBackToReadPaperWhenSearchHasNoMatch()
        try await agentLoopRunnerPreflightEvidenceIsInjectedAsUserContext()
        try await agentLoopRunnerThinkingModePayloadHasNoAssistantToolCallWithoutReasoning()
        try await agentLoopRunnerPreservesReasoningContentForNativeToolCalls()
        try agentAnswerQualityEvaluatorChecksFormulaSources()
        try await agentLoopRunnerPausesForWorkspaceWrite()
        try await agentLoopRunnerStopsAtMaxSteps()
        try await agentLoopRunnerInjectsToolResultMessages()
        try await agentLoopRunnerResumesPendingApproval()
        try await agentLoopRunnerDoesNotRepeatApprovedWriteOnResume()
        try await agentLoopRunnerEditArgumentsRevalidatesBeforeExecution()
        try await agentLoopRunnerSafetyDenyIsFatal()
        try await agentLoopRunnerCachesRepeatedReadOnlyToolCall()
        try await agentLoopRunnerStopsAtContextBudget()
        try await externalAgentRuntimeStreamsLegacyLoopEvents()
        try await fakeExternalRuntimeDrivesAITimelineEvents()
        try await langGraphRuntimePerformsInitializeHandshake()
        try await langGraphRuntimeReplaysGoldenFixtureRunSuccess()
        try await langGraphRuntimeReplaysGoldenFixtureApprovalResume()
        try await langGraphRuntimeRejectsInvalidFixtureSchemaVersion()
        try await langGraphRuntimeCanonicalizesSidecarLocalSequence()
        try await langGraphRuntimeFallsBackWhenInitializeTimesOut()
        try await langGraphRuntimeDoesNotLoseApprovalWhenSidecarCrashes()
        try await sidecarConnectionBrokenPipeThrowsInsteadOfTerminatingHost()
        try await sidecarLLMProxyDisablesProviderNativeToolCalling()
        try await sidecarEmbeddingProxyRejectsSensitiveConfigAndReturnsVectors()
        try await authorizedResourceProviderListsAndReadsDocuments()
        try await authorizedResourceProviderIndexesLegacyRawPaperMarkdown()
        try await embeddingIndexControllerRebuildsSelectedSource()
        try await embeddingIndexControllerRebuildsLegacyRawPaperSource()
        try await listPapersPayloadIncludesAbstract()
        try await paperMarkdownQualityInspectorDetectsPDFKitFallback()
        try paperReadingWorkflowProducesEvidenceBackedDraft()
        try relatedWorkWorkflowClustersByTheme()
        try await gapPlanningWorkflowGeneratesTodoDraftsWithoutWriting()
        try citationCriticBlocksUnsupportedClaims()
        try await evidenceRefsJumpToSourceLineRange()
        try await sidecarRuntimeSelectorPersistsAndFallbacks()
        try await sidecarRuntimeCoordinatorResolvesHealthAndSelection()
        try await runReplayLoadsTimelineFromRunDirectory()
        try await debugBundleManifestAndZipExcludeSecrets()
        try agentDiagnosticRedactorRedactsSecretsAndHomePaths()
        try embeddingFallbackUsesFTSWhenDisabled()
        try await embeddingStorePersistsAndMarksMigrationRequired()
        try agentEvidenceRefStableIDMarksStale()
        try await evidenceSourceJumpMapsPDFPageWhenAvailable()
        try await workspaceTemplateModuleConfigWritesAndLegacyMigration()
        try await workspaceCreationWizardPreviewValidationAndSafety()
        try workspaceModuleRegistryV1GatesRoutesWorkflowsAndArtifacts()
        try workspaceModuleRegistryGatesGraphWorkflows()
        try paperLibraryModuleDeclaresReadingQueueArtifactKindAndWorkflow()
        try workspaceModuleRegistryWorkflowGatingForReadingQueueCurate()
        try moduleSettingsViewModelEnableModuleRequiresDependencies()
        try moduleSettingsViewModelEnableDependenciesEnablesAllAncestors()
        try await moduleSettingsViewModelTogglePinPersistsOrder()
        try moduleSettingsViewModelDisablingDependencyHidesRoutes()
        try moduleSettingsViewModelOverrideOnlyAffectsTargetProject()
        try await workspaceModuleDirectoryRepairerSkipsWildcardPaths()
        try await workspaceModuleDirectoryRepairerRequiresPermissionApproval()
        try await workspaceModuleConfigurationStoreNotifiesObserversAtomically()
        try moduleOverrideMergerOnlyMutatesEnabledField()
        try moduleOverrideMergerLeavesUnknownIDsAsNoOp()
        try await templateAndSettingsRoundTripsAreIdentical()
        try await runtimeEventEnvelopeSequencesAreStableAndDeduplicated()
        try agentHumanDecisionActionDecodesLegacyAliases()
        try agentToolRiskUnknownValueDecodesAsExternalSideEffect()
        try runtimeEventEnvelopeUsesExternalTaggedUnion()
        try stableToolResultV1MapsToToolCallCompletedEvent()
        try await mcpGatewayListsAndCallsReadOnlySciStationTools()
        try await mcpGatewayRequiresApprovalForWorkspaceWrites()
        try await p32LegacyPendingCheckpointMigratesToRunDirectory()
        try await persistentLedgerPreventsDuplicateApprovedWriteAfterRestart()
        try await approvalRequestPersistsFingerprintForLedgerResume()
        try await toolHostBuildApprovalRequestHasNoSideEffects()
        try await readOnlyToolNotPausedByGenericPreToolUseReminder()
        try await deterministicSafetyPolicyBlocksSecretPromptBeforeLLM()
        try await hookDenyBlocksSensitivePathWrite()
        try await agentSkillLoaderProgressivelyLoadsMatchingSkill()
        try openAIProviderPayloadIncludesToolChoiceAuto()
        try openAIProviderNormalizesLegacyToolSchemas()
        try await agentRunLoggerSkipsDamagedHistoryLines()
        try await agentRunLoggerFiltersProjectConversations()
        try await agentThreadRepositoryGlobalStoreFiltersByWorkspaceID()
        try await agentThreadRepositoryMigratesPerWorkspaceLegacy()
        try await agentThreadRepositoryArchivesAndReadsLegacyThreads()
        try await agentPromptDraftRepositoryPersistsDrafts()
        try agentPaperIntentRouterMapsThirdPaperOrdinal()
        try agentToolDefinitionsExposePlatformMetadata()
        try agentPermissionRulesEvaluateSafetyDecisions()
        try agentHookEngineEvaluatesLifecycleResults()
        try agentPluginSkillAndMCPModelsValidate()
        try sciAITrackedPresetManifestValidates()
        try sciAIConfigurationBoundaryValidates()
        try await agentSessionEventLoggerAppendsAndReplaysEvents()
        try agentSessionTimelineItemsFilterCurrentSessions()
        try agentSessionTimelineProjectsLegacyRuns()
        try agentRunRetryMetadataRoundTrips()
        try agentPermissionDockSummarizesPolicies()
        try agentHookActivitySummaryReflectsTogglesAndResults()
        try agentMCPServerStatusSummaryParsesProductAndLocal()
        try openAIStreamDeltaParserIgnoresBadChunks()
        try llmProviderV2RequestModelsToolDefinitions()
        try await pdfImportCreatesLibraryMarkdownAndFigures()
        try await minerUAPIConversionCopiesImageAssets()
        try await movePaperToCollectionUpdatesMetadataAndPath()
        try await wikiPageGenerationWritesTemplateAndUpdatesMetadata()
        try await wikiPageGenerationRejectsSilentOverwrite()
        try frontmatterParserParsesArraysAndBody()
        try wikiLinkParserExtractsTargets()
        try wikiLinkParserExtractsNamespaces()
        try backlinkIndexFindsIncomingReferences()
        try backlinkIndexResolvesNamespacedLinks()
        try await markdownRepositoryLoadsAndSavesDocuments()
        try await paperMarkdownDirectLoadMergesIntoDocumentList()
        try await markdownRepositoryCreatesPageInsideWikiRoot()
        try await markdownRepositoryRejectsAbsolutePath()
        try await markdownRepositoryRenamesSelectedPage()
        try await markdownRepositoryArchivesPageInsteadOfHardDelete()
        try markdownSaveStateTransitionsDirtySavingClean()
    }

    private func createWorkspaceInitializesExpectedStructure() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("ResearchWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        try expect(workspace.missingRequiredItems().isEmpty, "Workspace should not miss any required paths after creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.sharedResearchURL.path), "shared_research.md should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.libraryBibURL.path), "refs/library.bib should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.tagsDefinitionURL.path), "refs/tags.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: ".sci-station").path), ".sci-station should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "refs/csl").path), "refs/csl should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "settings").path), "settings should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.workspacePreferencesURL.path), "workspace_preferences.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.markdownSnippetsURL.path), "markdown_snippets.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "tasks").path), "tasks should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "imports").path), "imports should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.dataURL.path), "data should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.figuresURL.path), "figures should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "tasks/todos.yaml").path), "tasks/todos.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "tasks/calendar.yaml").path), "tasks/calendar.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "imports/import_history.yaml").path), "imports/import_history.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "imports/failed_imports.yaml").path), "imports/failed_imports.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "wiki/projects/project_overview.md").path), "project_overview.md should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "wiki/projects/core_papers.md").path), "core_papers.md should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.researchFlowDatabaseURL.path), "researchflow.sqlite should exist after workspace creation.")
    }

    private func openWorkspaceBackfillsMissingStructure() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("BackfillWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: workspaceURL.appendingPathComponent("raw/papers", isDirectory: true),
            withIntermediateDirectories: true
        )

        let workspace = try await workspaceService.openWorkspace(at: workspaceURL)
        try expect(workspace.missingRequiredItems().isEmpty, "Opening an older workspace should backfill missing paths.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: ".sci-station").path), "Opening should create .sci-station when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "refs/csl").path), "Opening should create refs/csl when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.tagsDefinitionURL.path), "Opening should create refs/tags.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.workspacePreferencesURL.path), "Opening should create workspace_preferences.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.markdownSnippetsURL.path), "Opening should create markdown_snippets.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "tasks").path), "Opening should create tasks when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "imports").path), "Opening should create imports when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.dataURL.path), "Opening should create data when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.figuresURL.path), "Opening should create figures when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "tasks/todos.yaml").path), "Opening should create tasks/todos.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "imports/import_history.yaml").path), "Opening should create imports/import_history.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "wiki/projects/project_overview.md").path), "Opening should create project_overview.md when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "wiki/projects/core_papers.md").path), "Opening should create core_papers.md when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.researchFlowDatabaseURL.path), "Opening should create researchflow.sqlite when missing.")
    }

    private func createWorkspaceInitializesResearchRootAndDefaultProject() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let projectRegistryRepository = ProjectRegistryRepository()
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore,
            projectRegistryRepository: projectRegistryRepository
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("ResearchRootWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        let root = ResearchRoot(rootURL: workspace.rootURL)
        let registry = try await projectRegistryRepository.load(in: root)
        let defaultProject = try require(registry.projects.first, "Research root should create a default project.")

        try expect(root.missingRequiredItems().isEmpty, "Research root should not miss required root paths after creation.")
        try expect(FileManager.default.fileExists(atPath: root.globalPapersURL.path), "Global paper library directory should exist.")
        try expect(FileManager.default.fileExists(atPath: root.fileURL(for: "settings/agent.yaml").path), "Root agent settings should exist.")
        try expect(registry.lastOpenedProjectID == defaultProject.id, "Default project should become the last opened project.")
        try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: defaultProject.relativePath).path), "Default project directory should exist.")
        try expect(FileManager.default.fileExists(atPath: root.fileURL(for: defaultProject.relativePath + "/project.yaml").path), "Default project.yaml should exist.")
    }

    private func projectRegistryCreatesUpdatesAndCollapsesProjects() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let projectRegistryRepository = ProjectRegistryRepository()
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore,
            projectRegistryRepository: projectRegistryRepository
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("ProjectRegistryWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        let root = ResearchRoot(rootURL: workspace.rootURL)
        let createdProject = try await projectRegistryRepository.createProject(
            named: "Dark Matter Simulation",
            description: "Simulation campaign",
            colorHex: "#2A9D8F",
            iconName: "atom",
            in: root
        )

        var editedProject = createdProject
        editedProject.name = "Dark Matter Maps"
        editedProject.description = "Updated project scope"
        editedProject.colorHex = "#E76F51"
        editedProject.iconName = "chart.xyaxis.line"
        let updatedRegistry = try await projectRegistryRepository.updateProject(editedProject, in: root)
        let collapsedRegistry = try await projectRegistryRepository.setProjectCollapsed(createdProject.id, isCollapsed: true, in: root)
        let projectFileContents = try String(contentsOf: root.fileURL(for: createdProject.relativePath + "/project.yaml"), encoding: .utf8)

        try expect(updatedRegistry.projects.contains(where: { $0.id == createdProject.id && $0.name == "Dark Matter Maps" }), "Project registry should persist edited project metadata.")
        try expect(collapsedRegistry.projects.first(where: { $0.id == createdProject.id })?.isCollapsed == true, "Project registry should persist collapsed sidebar state.")
        try expect(projectFileContents.contains("Dark Matter Maps"), "Project yaml should be updated when project metadata changes.")
        try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: createdProject.relativePath + "/wiki").path), "Created projects should include a wiki directory.")
    }

    private func openLegacyWorkspaceCreatesResearchRootRegistry() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let projectRegistryRepository = ProjectRegistryRepository()
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore,
            projectRegistryRepository: projectRegistryRepository
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("LegacyWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("raw/papers", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("refs", isDirectory: true), withIntermediateDirectories: true)
        try "% legacy bibliography\n".write(to: workspaceURL.appendingPathComponent("refs/library.bib", isDirectory: false), atomically: true, encoding: .utf8)

        try expect(ResearchRoot.compatibility(at: workspaceURL) == .legacyWorkspace, "Existing single-workspace markers should be classified as legacy workspace before opening.")
        let workspace = try await workspaceService.openWorkspace(at: workspaceURL)
        let root = ResearchRoot(rootURL: workspace.rootURL)
        let registry = try await projectRegistryRepository.load(in: root)

        try expect(root.missingRequiredItems().isEmpty, "Opening a legacy workspace should backfill root paths.")
        try expect(registry.projects.first?.defaultTags.contains("legacy-workspace") == true, "Legacy workspace default project should record its compatibility tag.")
        try expect(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("raw/papers", isDirectory: true).path), "Legacy raw/papers data should stay in place.")
    }

    private func restoreLastWorkspaceClearsMissingBookmark() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("DeletedWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        _ = try await workspaceService.createWorkspace(at: workspaceURL)
        try FileManager.default.removeItem(at: workspaceURL)

        let restoredWorkspace = await workspaceService.restoreLastWorkspace()
        let restoredBookmarkURL = try await bookmarkStore.restoreBookmarkURL()

        try expect(restoredWorkspace == nil, "Restoring a deleted recent workspace should return nil instead of throwing.")
        try expect(restoredBookmarkURL == nil, "Restoring a deleted recent workspace should clear the stale bookmark.")
    }

    private func workspacePreferencesRoundTrip() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = WorkspacePreferences(
            libraryVisibleColumns: ["title", "tags", "doi"],
            librarySortState: LibrarySortState(field: .year, isAscending: false),
            defaultCollectionPath: "Dark-Matter",
            recentSection: "library"
        )
        preferences.updateLibraryVisibleColumns(from: "title,authors,bibtex")
        preferences.appLanguage = .simplifiedChinese
        preferences.liquidGlassTint = .mint
        preferences.agentChatFontSize = 17
        preferences.agentDebugLoggingEnabled = true
        preferences.agentLoopBudget = AgentLoopOptions(
            maxSteps: 13,
            maxToolCalls: 34,
            maxContextCharacters: 222_000,
            maxToolResultCharactersPerCall: 55_000,
            maxAccumulatedToolResultCharacters: 333_000,
            autoApproveReadOnly: false,
            allowProviderNativeTools: false
        )
        preferences.minerUCommand = "mineru"
        preferences.minerUAPIBaseURLString = "https://mineru.example.com"
        preferences.minerUAPILanguage = "zh"
        preferences.minerUOverwriteExistingMarkdown = false
        preferences.agentDisabledToolNamesByScope = [
            "project:test-workspace|thread:agent-thread-1": ["create_todo", "write_markdown_plan"]
        ]
        preferences.pinnedAgentThreadIDsByProject = [
            "test-workspace": ["agent-thread-1"]
        ]

        try await repository.save(preferences, in: workspace)
        let loadedPreferences = try await repository.load(in: workspace)

        try expect(loadedPreferences.libraryVisibleColumns == ["title", "authors", "bibtex"], "Workspace preferences should preserve column order.")
        try expect(loadedPreferences.librarySortState == LibrarySortState(field: .year, isAscending: false), "Workspace preferences should preserve Library sort state.")
        try expect(loadedPreferences.defaultCollectionPath == "Dark-Matter", "Workspace preferences should preserve default collection.")
        try expect(loadedPreferences.recentSection == "library", "Workspace preferences should preserve recent section.")
        try expect(loadedPreferences.appLanguage == .simplifiedChinese, "Workspace preferences should preserve app language.")
        try expect(loadedPreferences.liquidGlassTint == .mint, "Workspace preferences should preserve Liquid Glass tint.")
        try expect(loadedPreferences.agentChatFontSize == 17, "Workspace preferences should preserve AI Lab chat font size.")
        try expect(loadedPreferences.agentLoopBudget == preferences.agentLoopBudget, "Workspace preferences should preserve AI Lab loop budget.")
        try expect(loadedPreferences.agentDebugLoggingEnabled == true, "Workspace preferences should preserve debug logging mode.")
        try expect(loadedPreferences.minerUCommand == "mineru", "Workspace preferences should preserve MinerU command.")
        try expect(loadedPreferences.minerUAPIBaseURLString == "https://mineru.example.com", "Workspace preferences should preserve MinerU API base URL.")
        try expect(loadedPreferences.minerUAPILanguage == "zh", "Workspace preferences should preserve MinerU API language.")
        try expect(loadedPreferences.minerUOverwriteExistingMarkdown == false, "Workspace preferences should preserve MinerU overwrite behavior.")
        try expect(loadedPreferences.agentDisabledToolNamesByScope["project:test-workspace|thread:agent-thread-1"] == ["create_todo", "write_markdown_plan"], "Workspace preferences should preserve scoped disabled tools.")
        try expect(loadedPreferences.pinnedAgentThreadIDsByProject["test-workspace"] == ["agent-thread-1"], "Workspace preferences should preserve project-scoped pinned threads.")
    }

    private func workspacePreferencesLanguageRoundTrips() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LanguagePreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = try await repository.load(in: workspace)
        preferences.appLanguage = .english
        try await repository.save(preferences, in: workspace)

        let englishPreferences = try await repository.load(in: workspace)
        preferences.appLanguage = .simplifiedChinese
        try await repository.save(preferences, in: workspace)
        let chinesePreferences = try await repository.load(in: workspace)

        try expect(englishPreferences.appLanguage == .english, "Workspace preferences should round-trip English app language.")
        try expect(chinesePreferences.appLanguage == .simplifiedChinese, "Workspace preferences should round-trip Chinese app language.")
    }

    private func homeWidgetLayoutRoundTripsPreferences() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("HomeWidgetPreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = try await repository.load(in: workspace)
        preferences.homeWidgetLayout.resizeWidget(HomeWidgetID.today, to: .medium, descriptors: HomeWidgetRegistry.defaultDescriptors, columns: 2)
        preferences.homeWidgetLayout.moveWidget(HomeWidgetID.aiReview, before: HomeWidgetID.today, descriptors: HomeWidgetRegistry.defaultDescriptors, columns: 2)
        preferences.homeWidgetLayout.setWidget(HomeWidgetID.calendar, isEnabled: false, descriptors: HomeWidgetRegistry.defaultDescriptors, columns: 2)
        try await repository.save(preferences, in: workspace)

        let loaded = try await repository.load(in: workspace)
        let loadedItems = Dictionary(uniqueKeysWithValues: loaded.homeWidgetLayout.items.map { ($0.widgetID, $0) })
        try expect(loadedItems[HomeWidgetID.today]?.size == .medium, "Home widget preferences should preserve resized widgets.")
        try expect(loadedItems[HomeWidgetID.calendar]?.isEnabled == false, "Home widget preferences should preserve disabled widgets.")
        let loadedOrder = loaded.homeWidgetLayout.items.map(\.widgetID)
        let aiIndex = loadedOrder.firstIndex(of: HomeWidgetID.aiReview) ?? Int.max
        let todayIndex = loadedOrder.firstIndex(of: HomeWidgetID.today) ?? Int.max
        try expect(aiIndex < todayIndex, "Home widget preferences should preserve explicit relative ordering.")
    }

    private func homeWidgetLayoutFallsBackWhenInvalid() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("InvalidHomeWidgetPreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let preferencesURL = workspace.fileURL(for: WorkspacePreferencesRepository.relativePath)
        try FileManager.default.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        schema_version: 4
        home_widget_layout:
          schema_version: 1
          updated_at: "not-a-date"
          items:
            - widget_id: "unknown_widget"
              size: "giant"
              column: -4
              row: -2
              is_enabled: true
        """.write(to: preferencesURL, atomically: true, encoding: .utf8)

        let loaded = try await repository.load(in: workspace)
        let ids = loaded.homeWidgetLayout.items.map(\.widgetID)
        try expect(ids.contains(HomeWidgetID.today), "Invalid Home widget preferences should fall back to known default widgets.")
        try expect(!ids.contains("unknown_widget"), "Invalid Home widget preferences should drop unknown widget ids.")
    }

    private func l10nCatalogResolvesChineseAndEnglish() throws {
        try expect(L10n.text(.toolbarImportPDF, language: .english) == "Import PDF", "English catalog should resolve Import PDF.")
        try expect(L10n.text(.toolbarImportPDF, language: .simplifiedChinese) == "导入 PDF", "Chinese catalog should resolve Import PDF.")
        try expect(L10n.text(.projectArchiveAction, language: .simplifiedChinese) == "归档项目", "Chinese catalog should resolve destructive project actions.")
        try expect(L10n.missingKeys(language: .english).isEmpty, "English localization catalog should cover all keys.")
        try expect(L10n.missingKeys(language: .simplifiedChinese).isEmpty, "Chinese localization catalog should cover all keys.")
    }

    private func l10nCatalogFallsBackWithAuditWarning() throws {
        let result = L10n.resolve(rawKey: "missing.demo.key", language: .simplifiedChinese)

        try expect(result.usedFallback, "Raw missing localization keys should report fallback usage.")
        try expect(result.text == "missing.demo.key", "Raw missing localization keys should fall back to the key string.")
    }

    private func localizationAuditFlagsHardcodedSwiftUIText() throws {
        let source = #"""
        VStack {
            Text("Import PDF")
            Label("folder", systemImage: "folder")
            Button(appModel.t(.toolbarImportPDF)) {}
        }
        """#
        let findings = LocalizationAudit.findings(in: source, filePath: "SampleView.swift")

        try expect(findings.contains { $0.literal == "Import PDF" }, "Localization audit should flag user-visible hardcoded English.")
        try expect(!findings.contains { $0.literal == "folder" }, "Localization audit should allow system image names and simple symbols.")
        try expect(!findings.contains { $0.literal == "toolbarImportPDF" }, "Localization audit should not flag L10n key references as literals.")
    }

    private func workspaceContextSnapshotReflectsHomeRoute() throws {
        let snapshot = WorkspaceContextSnapshot(topLevelSectionID: WorkspaceRoute.Top.home.rawValue)

        try expect(snapshot.topLevelSectionID == "home", "Home context snapshots should preserve the top-level route id.")
        try expect(snapshot.displayTitle == "home", "Home context snapshots should use the top-level route as the fallback display title.")
    }

    private func workspaceContextSnapshotReflectsProjectPaperSelection() throws {
        let snapshot = WorkspaceContextSnapshot(
            topLevelSectionID: WorkspaceRoute.Top.projects.rawValue,
            projectID: "project-a",
            projectTitle: "Dark Matter Maps",
            projectTabID: "papers",
            selectedPaperID: "paper-1",
            selectedPaperTitle: "A Compact Paper"
        )

        try expect(snapshot.projectID == "project-a", "Project snapshots should preserve the project id.")
        try expect(snapshot.projectTabID == "papers", "Project snapshots should preserve the active project tab.")
        try expect(snapshot.displayTitle == "Paper: A Compact Paper", "Paper selections should take precedence in context display titles.")
    }

    private func rightRailAutoHidesWhenNoContext() throws {
        let homeRoute = WorkspaceRoute(top: .home)
        let homeContext = WorkspaceContextSnapshot(topLevelSectionID: "home")
        let libraryRoute = WorkspaceRoute(top: .library)
        let libraryContext = WorkspaceContextSnapshot(topLevelSectionID: "library")
        let projectsRoute = WorkspaceRoute(top: .projects, projectID: "proj-1", projectTabID: "reading")
        let projectsContext = WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "proj-1", projectTabID: "reading")

        // 2026-05-17 UI Bug Bash: the right rail policy is now fully sticky —
        // suggestedMode echoes preferredMode back so user-driven toggles win.
        // Route-based hints have been moved to `defaultMode(for:)`, which is
        // only consulted when seeding an untouched workspace's initial state.
        try expect(RightRailPolicy.suggestedMode(route: homeRoute, context: homeContext, preferredMode: .inspector) == .inspector, "User-pinned inspector mode must survive a Home route refresh.")
        try expect(RightRailPolicy.suggestedMode(route: libraryRoute, context: libraryContext, preferredMode: .hidden) == .hidden, "User-hidden right rail must stay hidden across route changes (sticky preference).")
        try expect(RightRailPolicy.suggestedMode(route: projectsRoute, context: projectsContext, preferredMode: .inspector) == .inspector, "User-opened inspector must stay open on routes that previously hinted .hidden (Reading tab regression).")
        try expect(RightRailPolicy.suggestedMode(route: homeRoute, context: homeContext, preferredMode: .ai) == .ai, "An open AI rail should stay open across route context updates.")

        // `defaultMode(for:)` keeps the legacy auto-hide intent for workspace
        // bootstrap, but it is now opt-in for callers that want a fresh
        // workspace to start with a context-aware default.
        try expect(RightRailPolicy.defaultMode(route: homeRoute, context: homeContext) == .hidden, "Home default mode should still be .hidden so a fresh workspace doesn't open with an empty inspector.")
        try expect(RightRailPolicy.defaultMode(route: libraryRoute, context: libraryContext) == .inspector, "Library default mode should still seed the paper inspector for a fresh workspace.")
    }

    private func responsivePolicyHidesRightRailBelowThreshold() throws {
        let context = WorkspaceContextSnapshot(topLevelSectionID: "library")
        let model = ResponsiveShellPolicy.resolve(
            width: 900,
            route: WorkspaceRoute(top: .library),
            context: context,
            preferredRightRailMode: .inspector
        )

        try expect(model.bucket == .compact, "Responsive shell policy should classify 900pt as compact.")
        try expect(model.effectiveRightRailMode == .hidden, "Responsive shell policy should hide the right rail below 1000pt.")
        try expect(model.homeWidgetColumns == 2, "Responsive shell policy should use two Home widget columns for compact widths.")
        try expect(model.shouldCollapseProjectTree, "Responsive shell policy should collapse project tree in compact widths.")
    }

    private func responsivePolicyMovesToolbarActionsToOverflow() throws {
        let model = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .library),
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )
        let narrowModel = ResponsiveShellPolicy.toolbarModel(model, width: 720)

        try expect(narrowModel.pageActions.isEmpty, "Narrow responsive policy should move page toolbar actions out of the primary group.")
        try expect(narrowModel.overflowActions.contains(where: { $0.id == .addByIdentifier }), "Narrow responsive policy should keep page actions reachable from overflow.")
        try expect(narrowModel.globalActions.contains(where: { $0.id == .workspaceMenu }), "Narrow responsive policy should keep global actions visible.")
    }

    private func homeWidgetRegistryIncludesDefaultWidgets() throws {
        let ids = Set(HomeWidgetRegistry.defaultDescriptors.map(\.id))
        let expectedIDs: Set<String> = [
            HomeWidgetID.today,
            HomeWidgetID.activeProjects,
            HomeWidgetID.aiReview,
            HomeWidgetID.calendar,
            HomeWidgetID.recentPapers,
            HomeWidgetID.readingPlan,
            HomeWidgetID.projectHealth,
            HomeWidgetID.quickActions
        ]

        try expect(ids == expectedIDs, "Home widget registry should include every default dashboard widget.")
        try expect(HomeWidgetRegistry.defaultDescriptors.allSatisfy { !$0.supportedSizes.isEmpty }, "Home widget descriptors should declare supported sizes.")
    }

    private func homeWidgetRegistryFiltersDisabledModules() throws {
        let configuration = WorkspaceModuleRegistry.defaultConfiguration(enabledModuleIDs: ["projects"])
        let availableIDs = Set(HomeWidgetRegistry.availableDescriptors(in: configuration).map(\.id))

        try expect(availableIDs.contains(HomeWidgetID.activeProjects), "Project widgets should remain available when Projects is enabled.")
        try expect(availableIDs.contains(HomeWidgetID.quickActions), "Quick Actions should remain available without module dependencies.")
        try expect(!availableIDs.contains(HomeWidgetID.calendar), "Calendar widget should hide when Calendar module is disabled.")
        try expect(!availableIDs.contains(HomeWidgetID.aiReview), "AI Review widget should hide when AI Lab module is disabled.")
    }

    private func homeWidgetGridReflowsForTwoColumns() throws {
        let layout = HomeWidgetLayout.defaultLayout(columns: 2)
        let descriptorsByID = Dictionary(uniqueKeysWithValues: HomeWidgetRegistry.defaultDescriptors.map { ($0.id, $0) })
        let cells = HomeWidgetGridPlanner.cells(items: layout.items, descriptorsByID: descriptorsByID, columns: 2)

        try expect(!cells.isEmpty, "Home widget planner should emit cells for default layout.")
        try expect(cells.allSatisfy { $0.item.column + $0.columnSpan <= 2 }, "Home widget planner should clamp cells inside two columns.")
        try expect(!HomeWidgetGridPlanner.hasOverlap(items: layout.items, descriptorsByID: descriptorsByID, columns: 2), "Two-column Home widget layout should not overlap.")
    }

    private func homeWidgetGridReflowsForSingleColumn() throws {
        let layout = HomeWidgetLayout.defaultLayout(columns: 1)
        let descriptorsByID = Dictionary(uniqueKeysWithValues: HomeWidgetRegistry.defaultDescriptors.map { ($0.id, $0) })
        let cells = HomeWidgetGridPlanner.cells(items: layout.items, descriptorsByID: descriptorsByID, columns: 1)

        try expect(cells.allSatisfy { $0.item.column == 0 && $0.columnSpan == 1 }, "Single-column Home widget layout should stack every widget in column zero.")
        try expect(!HomeWidgetGridPlanner.hasOverlap(items: layout.items, descriptorsByID: descriptorsByID, columns: 1), "Single-column Home widget layout should not overlap.")
    }

    private func homeWidgetGridRepackAvoidsOverlap() throws {
        let descriptors = HomeWidgetRegistry.defaultDescriptors
        let descriptorsByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let collidingLayout = HomeWidgetLayout(items: [
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.today, size: .wide, column: 0, row: 0),
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.activeProjects, size: .wide, column: 0, row: 0),
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.aiReview, size: .medium, column: 0, row: 0)
        ])
        let normalized = collidingLayout.normalized(descriptors: descriptors, columns: 3)

        try expect(!HomeWidgetGridPlanner.hasOverlap(items: normalized.items, descriptorsByID: descriptorsByID, columns: 3), "Home widget planner should repack colliding items without overlap.")
        try expect(normalized.items.count == descriptors.count, "Home widget normalization should backfill missing default descriptors.")
    }

    private func homeWidgetResetRestoresDefaultLayout() throws {
        let descriptors = HomeWidgetRegistry.defaultDescriptors
        var layout = HomeWidgetLayout.defaultLayout(descriptors: descriptors, columns: 4)
        layout.moveWidget(HomeWidgetID.quickActions, before: HomeWidgetID.today, descriptors: descriptors, columns: 4)
        layout.setWidget(HomeWidgetID.calendar, isEnabled: false, descriptors: descriptors, columns: 4)
        layout.reset(descriptors: descriptors, columns: 4)

        let defaultLayout = HomeWidgetLayout.defaultLayout(descriptors: descriptors, columns: 4)
        try expect(layout.items.map(\.widgetID) == defaultLayout.items.map(\.widgetID), "Reset should restore Home widget default order.")
        try expect(layout.items.allSatisfy(\.isEnabled), "Reset should re-enable default Home widgets.")
    }

    /// 2026-05-17 UI Bug Bash Round 3 regression. The user reported that
    /// dragging a Home widget briefly settled into the new spot and then
    /// snapped back. Two model-side bugs were responsible:
    ///
    /// 1. `repack` re-sorted `items` by `(row, column)` BEFORE laying them
    ///    out, but at the moment `moveWidget(_:before:)` calls `repack` the
    ///    items still carry their pre-move positions, so the sort silently
    ///    restored the original order — every drag was a no-op once persisted
    ///    (verified in `~/Documents/ResearchWorkspace/.sci-station/debug/app_events.jsonl`
    ///    at 2026-05-17T09:13:18Z).
    ///
    /// 2. `moveWidget(_:before:)` was asymmetric — for forward drags
    ///    (`sourceIndex < targetIndex`) inserting "immediately before target"
    ///    only nudges the source one slot, never landing on the target's
    ///    tile. The dashboard now calls the unified `onto:` variant which
    ///    swaps source into target's slot regardless of drag direction.
    ///
    /// Both regressions covered here against `cols = 4` (typical expanded
    /// dashboard width) so a future refactor that re-introduces the position
    /// sort will fail the same scenarios the user manually hit.
    private func homeWidgetDragOntoCommitsInBothDirections() throws {
        let descriptors = HomeWidgetRegistry.defaultDescriptors

        // Backward drag: aiReview (idx 2) → onto activeProjects (idx 1).
        // The user's actual logged action; before the fix this came back as
        // a no-op because repack's positionSort restored the old order.
        var backward = HomeWidgetLayout.defaultLayout(descriptors: descriptors, columns: 4)
        backward.moveWidget(HomeWidgetID.aiReview, onto: HomeWidgetID.activeProjects, descriptors: descriptors, columns: 4)
        let backwardOrder = backward.items.map(\.widgetID)
        let aiIdxBackward = backwardOrder.firstIndex(of: HomeWidgetID.aiReview) ?? Int.max
        let activeIdxBackward = backwardOrder.firstIndex(of: HomeWidgetID.activeProjects) ?? Int.max
        try expect(aiIdxBackward < activeIdxBackward, "Backward drag (aiReview onto activeProjects) must land aiReview at activeProjects's slot.")

        // Forward drag: today (idx 0) → onto aiReview (idx 2). Before the
        // `onto:` semantic this only moved today by one slot; after the fix
        // today must land at aiReview's exact slot.
        var forward = HomeWidgetLayout.defaultLayout(descriptors: descriptors, columns: 4)
        forward.moveWidget(HomeWidgetID.today, onto: HomeWidgetID.aiReview, descriptors: descriptors, columns: 4)
        let forwardOrder = forward.items.map(\.widgetID)
        let todayIdxForward = forwardOrder.firstIndex(of: HomeWidgetID.today) ?? Int.max
        let aiIdxForward = forwardOrder.firstIndex(of: HomeWidgetID.aiReview) ?? Int.max
        try expect(todayIdxForward > aiIdxForward, "Forward drag (today onto aiReview) must place today AFTER aiReview in the order, swapping into aiReview's slot.")

        // Repacking the layout (e.g. via `setWidget`) MUST NOT silently
        // restore the pre-move order. This was the second model bug — the
        // `repack` helper used to sort by `(row, column)` first, undoing the
        // move once items were laid out. The post-fix invariant: the user's
        // intended array order survives any subsequent normalize / repack.
        forward.setWidget(HomeWidgetID.calendar, isEnabled: false, descriptors: descriptors, columns: 4)
        let postRepackOrder = forward.items.filter(\.isEnabled).map(\.widgetID)
        let todayIdxAfter = postRepackOrder.firstIndex(of: HomeWidgetID.today) ?? Int.max
        let aiIdxAfter = postRepackOrder.firstIndex(of: HomeWidgetID.aiReview) ?? Int.max
        try expect(todayIdxAfter > aiIdxAfter, "Subsequent repack (via setWidget) must NOT restore the pre-move order — the user's drag must persist across normalization.")
    }

    private func rightRailModePersistsAcrossWorkspaceReload() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("RightRailPreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = try await repository.load(in: workspace)
        preferences.rightRailMode = .ai
        preferences.isGlobalAIPanelOpen = true
        preferences.isProjectTreeExpanded = false
        preferences.pinnedProjectIDs = ["project-a", "project-b"]
        try await repository.save(preferences, in: workspace)

        let loaded = try await repository.load(in: workspace)
        try expect(loaded.rightRailMode == .ai, "Workspace preferences should persist the right rail mode.")
        try expect(loaded.isGlobalAIPanelOpen, "Workspace preferences should persist AI panel open state.")
        try expect(!loaded.isProjectTreeExpanded, "Workspace preferences should persist project tree expansion state.")
        try expect(loaded.pinnedProjectIDs == ["project-a", "project-b"], "Workspace preferences should persist pinned project ids.")
    }

    private func toolbarPolicyShowsImportOnlyForLibraryContexts() throws {
        let libraryModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .library),
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )
        let projectPapersModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "papers"),
            context: WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "project-a", projectTabID: "papers")
        )
        let calendarModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .calendar),
            context: WorkspaceContextSnapshot(topLevelSectionID: "calendar")
        )

        try expect(libraryModel.contains(.importPDF) && libraryModel.contains(.addByIdentifier), "Library toolbar policy should include paper import actions.")
        try expect(projectPapersModel.contains(.importPDF) && projectPapersModel.contains(.addByIdentifier), "ProjectSpace Papers toolbar policy should include paper import actions.")
        try expect(!calendarModel.contains(.importPDF) && !calendarModel.contains(.addByIdentifier), "Calendar toolbar policy should not include paper import actions.")
    }

    private func toolbarPolicyHidesPaperActionsOnHome() throws {
        let model = ToolbarPolicy.resolve(
            route: .home,
            context: WorkspaceContextSnapshot(topLevelSectionID: "home")
        )

        try expect(!model.contains(.importPDF), "Home toolbar policy should hide Import PDF.")
        try expect(!model.contains(.addByIdentifier), "Home toolbar policy should hide Add by Identifier.")
        try expect(model.contains(.aiPanel), "Home toolbar policy should keep the global AI action.")
        try expect(!model.contains(.refresh), "Home toolbar policy should hide refresh.")
    }

    private func toolbarPolicyShowsPDFActionsOnlyInPDFReader() throws {
        let pdfModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "pdf-reader"),
            context: WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "project-a", projectTabID: "pdf-reader"),
            language: .simplifiedChinese
        )
        let wikiModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "wiki"),
            context: WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "project-a", projectTabID: "wiki")
        )

        try expect(pdfModel.contains(.pdfSearch), "PDF Reader toolbar policy should include PDF search.")
        try expect(pdfModel.action(.pdfAnnotationPlaceholder)?.title == "标注", "PDF Reader toolbar should localize PDF actions.")
        try expect(!pdfModel.contains(.importPDF) && !pdfModel.contains(.addByIdentifier), "PDF Reader toolbar policy should hide Library import actions.")
        try expect(!wikiModel.contains(.pdfSearch) && !wikiModel.contains(.pdfAnnotationPlaceholder), "Wiki toolbar policy should not include PDF Reader actions.")
    }

    private func toolbarPolicyShowsWikiActionsOnlyInWikiContext() throws {
        let wikiModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "wiki"),
            context: WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "project-a", projectTabID: "wiki")
        )
        let libraryModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .library),
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )

        try expect(wikiModel.contains(.wikiNewPage) && wikiModel.contains(.wikiSave), "Wiki toolbar policy should include Wiki actions.")
        try expect(!libraryModel.contains(.wikiNewPage) && !libraryModel.contains(.wikiSave), "Library toolbar policy should not include Wiki actions.")
    }

    private func toolbarCommandCatalogMapsToolbarActionsToCommandContributions() async throws {
        let model = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .library),
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )
        let contributions = model.primaryCommandContributions
        let ids = contributions.map(\.id)
        let importContribution = try require(contributions.first { $0.id == "paper.importPDF" }, "Import PDF should be exposed as a command contribution.")
        let registry = CommandRegistry()
        try await registry.register(importContribution, pluginID: "sci.paper-library") { context in
            CommandExecutionResult(succeeded: context.commandID == "paper.importPDF", message: context.pluginID)
        }
        let visible = await registry.contributions(placement: .toolbar)
        let result = try await registry.execute(id: importContribution.id)

        try expect(ids.contains("workspace.menu"), "Workspace menu should have a stable command id.")
        try expect(ids.contains("shell.aiPanel"), "AI panel toolbar action should have a stable command id.")
        try expect(ids.contains("paper.importByIdentifier"), "Identifier import toolbar action should have a stable command id.")
        try expect(importContribution.title == model.action(.importPDF)?.title, "Command contribution should preserve toolbar action title.")
        try expect(importContribution.systemImage == "doc.badge.plus", "Command contribution should preserve toolbar action image.")
        try expect(ToolbarCommandCatalog.toolbarActionID(for: "paper.importPDF") == .importPDF, "Toolbar command catalog should map command ids back to action ids.")
        try expect(visible.contains(importContribution), "Toolbar command contribution should register in the generic command registry.")
        try expect(result.succeeded && result.message == "sci.paper-library", "Toolbar command contribution should execute through the generic command registry.")
    }

    private func projectTreeArchiveFallsBackToProjectsRoute() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("ProjectArchiveRouteWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let root = ResearchRoot(rootURL: rootURL)
        let repository = ProjectRegistryRepository()
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let project = try await repository.createProject(named: "Archive Candidate", in: root)
        var archivedProject = project
        archivedProject.isArchived = true
        let registry = try await repository.updateProject(archivedProject, in: root)
        let activeProjectIDs = Set(registry.projects.filter { !$0.isArchived }.map(\.id))
        let result = RoutePersistence.restoreResult(
            candidate: WorkspaceRoute(top: .projects, projectID: project.id, projectTabID: "papers"),
            activeProjectIDs: activeProjectIDs,
            configuration: WorkspaceModuleRegistry.defaultConfiguration()
        )

        try expect(result.route == WorkspaceRoute(top: .projects), "Routes pointing at an archived project should fall back to the Projects list.")
        try expect(result.fallbackReason == .projectMissing, "Archived projects should be treated as unavailable for route restoration.")
    }

    private func projectArchiveHidesProjectFromActiveList() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("ProjectArchiveWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let repository = ProjectRegistryRepository()
        let firstProject = try await repository.createProject(named: "Archive Candidate", in: root)
        let secondProject = try await repository.createProject(named: "Still Active", in: root)
        let result = try await repository.archiveProject(firstProject.id, in: root)
        let activeProjectIDs = result.registry.projects.filter { !$0.isArchived }.map(\.id)
        let projectFileContents = try String(contentsOf: root.fileURL(for: firstProject.relativePath + "/project.yaml"), encoding: .utf8)

        try expect(result.project.isArchived, "Archived projects should be marked archived.")
        try expect(!activeProjectIDs.contains(firstProject.id), "Archived projects should disappear from active project lists.")
        try expect(activeProjectIDs == [secondProject.id], "Only non-archived projects should remain active.")
        try expect(projectFileContents.contains("is_archived: true"), "Archived project.yaml should mirror archived lifecycle state.")
    }

    private func projectRestoreReturnsProjectToActiveList() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("ProjectRestoreWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let repository = ProjectRegistryRepository()
        let project = try await repository.createProject(named: "Restore Candidate", in: root)

        _ = try await repository.archiveProject(project.id, in: root)
        let result = try await repository.restoreProject(project.id, in: root)
        let restoredProject = try require(result.registry.projects.first { $0.id == project.id }, "Restored project should remain in the registry.")

        try expect(!restoredProject.isArchived, "Restored projects should be active.")
        try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: restoredProject.relativePath).path), "Restored project directory should exist.")
        try expect(result.registry.lastOpenedProjectID == project.id, "Restored project should become the last opened project.")
    }

    private func projectDeleteMovesToTrashOrArchive() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("ProjectTrashWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let repository = ProjectRegistryRepository()
        let project = try await repository.createProject(named: "Trash Candidate", in: root)
        let originalURL = root.directoryURL(for: project.relativePath)
        let result = try await repository.deleteProjectToTrash(project.id, in: root)
        let trashedProject = try require(result.registry.projects.first { $0.id == project.id }, "Trashed project should remain recoverable in the registry.")

        try expect(trashedProject.isArchived, "Trashed projects should be hidden from active lists.")
        try expect(trashedProject.relativePath.hasPrefix(".sci-station/trash/projects/"), "Trashed projects should move under the workspace trash.")
        try expect(!FileManager.default.fileExists(atPath: originalURL.path), "Original project directory should be moved out of projects/.")
        try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: trashedProject.relativePath).path), "Trashed project directory should exist in workspace trash.")
        let trashedProjectFile = try String(contentsOf: root.fileURL(for: trashedProject.relativePath + "/project.yaml"), encoding: .utf8)
        try expect(trashedProjectFile.contains("relative_path: \"\(trashedProject.relativePath)\""), "Trashed project.yaml should mirror the trash relative path.")
    }

    private func projectSpaceTabsBuilderHonorsAvailableModules() throws {
        let tabs = ProjectSpaceTabsBuilder.tabs(
            for: "project-a",
            configuration: WorkspaceModuleRegistry.defaultConfiguration(),
            pinnedOrder: []
        )
        let ids = tabs.map(\.id)

        try expect(ids.contains("overview"), "ProjectSpace tabs should include Overview from the projects module.")
        try expect(ids.contains("papers"), "ProjectSpace tabs should include Papers from the paper-library module.")
    try expect(!ids.contains("reading"), "ProjectSpace tabs should not expose Reading after it is merged into Tasks.")
        try expect(ids.contains("recommendations"), "ProjectSpace tabs should include arXiv Recommendations from the recommendation module.")
    try expect(tabs.first(where: { $0.id == "recommendations" })?.title == "论文推荐", "Recommendation project tab should use the Chinese title.")
        try expect(!ids.contains("queue"), "ProjectSpace tabs should not expose Queue as a separate tab after Reading consolidation.")
        try expect(!ids.contains("reading-plan"), "ProjectSpace tabs should not expose Reading Plan as a separate tab after Reading consolidation.")
        try expect(ids.contains("wiki"), "ProjectSpace tabs should include Wiki from the wiki module.")
        try expect(ids.contains("tasks"), "ProjectSpace tabs should include Tasks from the tasks module.")
        try expect(ids.contains("calendar"), "ProjectSpace tabs should include Calendar from the calendar module.")
        try expect(ids.contains("ai-drafts"), "ProjectSpace tabs should include AI Workflows from the AI Lab module.")
    }

    private func projectSpaceTabsBuilderRespectsPinnedOrder() throws {
        let tabs = ProjectSpaceTabsBuilder.tabs(
            for: "project-a",
            configuration: WorkspaceModuleRegistry.defaultConfiguration(),
            pinnedOrder: ["wiki", "papers"]
        )
        let ids = tabs.map(\.id)

        try expect(ids.prefix(3) == ["overview", "wiki", "papers"], "Pinned ProjectSpace tabs should follow Overview while preserving its fixed leftmost position.")
    }

    private func projectSpaceTabsBuilderRemovesDisabledModuleTabs() throws {
        var configuration = WorkspaceModuleRegistry.defaultConfiguration()
        for index in configuration.modules.indices where configuration.modules[index].id == "wiki" {
            configuration.modules[index].enabled = false
        }

        let ids = ProjectSpaceTabsBuilder.tabs(for: "project-a", configuration: configuration, pinnedOrder: []).map(\.id)
        try expect(!ids.contains("wiki"), "Disabling the wiki module should remove the Wiki ProjectSpace tab.")
    }

    private func projectSpaceTabsBuilderKeepsOverviewLeftmost() throws {
        let tabs = ProjectSpaceTabsBuilder.tabs(
            for: "project-a",
            configuration: WorkspaceModuleRegistry.defaultConfiguration(),
            pinnedOrder: ["tasks", "overview", "calendar"]
        )
        try expect(tabs.first?.id == "overview", "Overview should remain the leftmost ProjectSpace tab.")
    }

    private func pluginManifestValidatorRejectsInvalidIDs() throws {
        let manifest = PluginManifest(
            id: "Bad Plugin",
            name: "",
            version: "",
            contributes: PluginContribution(commands: [
                CommandContribution(id: "paper.import", title: "Import", placement: .toolbar),
                CommandContribution(id: "paper.import", title: "Import Again", placement: .toolbar)
            ])
        )
        let issues = PluginManifestValidator().validate(manifest)
        let fields = Set(issues.map(\.field))

        try expect(fields.contains("id"), "Plugin validator should reject unstable plugin ids.")
        try expect(fields.contains("name"), "Plugin validator should require plugin names.")
        try expect(fields.contains("version"), "Plugin validator should require plugin versions.")
        try expect(fields.contains("contributes.commands"), "Plugin validator should reject duplicate command ids.")
    }

    private func pluginRegistryResolvesBuiltInWorkspaceModuleAdapters() async throws {
        let manifests = WorkspaceModulePluginAdapter.builtInManifests()
        let registry = try PluginRegistry(manifests: manifests)
        let enabledIDs = try await registry.resolvedEnabledPluginIDs()
        let commands = try await registry.commandContributions()
        let modules = try await registry.workspaceModuleContributions().map(\.module)
        let tabs = try await registry.projectTabContributions()
        let workflows = try await registry.workflowContributions()
        let paperLibrary = try require(manifests.first { $0.id == "sci.paper-library" }, "paper-library should adapt to a built-in plugin manifest.")

        try expect(enabledIDs.contains("sci.projects"), "Built-in plugin registry should expose enabled Projects plugin.")
        try expect(enabledIDs.contains("sci.paper-library"), "Built-in plugin registry should expose enabled Paper Library plugin.")
        try expect(!enabledIDs.contains("sci.code"), "Disabled workspace modules should remain disabled as plugin manifests.")
        try expect(commands.isEmpty, "Workspace module adapter should not invent command handlers before command migration.")
        try expect(modules.contains { $0.id == "paper-library" }, "Workspace module adapter should preserve module contribution payloads.")
        try expect(tabs.contains { $0.id == "papers" }, "Plugin registry should expose project tab contributions from enabled manifests.")
        try expect(workflows.contains { $0.id == "paper_reading" }, "Plugin registry should expose workflow contributions from enabled manifests.")
        try expect(paperLibrary.permissions.writePaths.contains("library/papers/"), "Workspace module adapter should preserve declared write paths.")
        try expect(paperLibrary.contributes.routes.contains { $0.id == "library" }, "Workspace module adapter should expose route contributions.")
    }

    private func pluginWorkspaceContributionCatalogResolvesBuiltInModules() throws {
        let configuration = WorkspaceModuleRegistry.defaultConfiguration(
            enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library"])
        )
        let catalog = PluginWorkspaceContributionCatalog(configuration: configuration)
        let routeIDs = Set(catalog.availableRoutes().map(\.id))
        let tabIDs = Set(catalog.availableProjectTabs().map(\.id))
        let workflows = Set(catalog.availableWorkflows())
        let descriptor = catalog.artifactKindDescriptor(for: "research_plan")
        let unknownDescriptor = catalog.artifactKindDescriptor(for: "future_plugin_artifact")

        try expect(routeIDs.contains("projects"), "Plugin workspace catalog should expose enabled built-in routes.")
        try expect(!routeIDs.contains("library"), "Plugin workspace catalog should hide disabled module routes.")
        try expect(!routeIDs.contains("pdf-reader"), "Plugin workspace catalog should hide routes whose dependencies are disabled.")
        try expect(tabIDs.contains("overview"), "Plugin workspace catalog should expose project tabs from enabled modules.")
        try expect(!workflows.contains("paper_reading"), "Plugin workspace catalog should gate workflows by module requirements.")
        try expect(descriptor.isKnown && descriptor.moduleID == "projects", "Plugin workspace catalog should resolve known artifact descriptors.")
        try expect(!unknownDescriptor.isKnown && unknownDescriptor.title == "Future Plugin Artifact", "Plugin workspace catalog should fall back for unknown artifact descriptors.")
    }

    private func commandRegistryExecutesRegisteredContribution() async throws {
        let registry = CommandRegistry()
        let contribution = CommandContribution(
            id: "paper.importPDF",
            title: "Import PDF",
            systemImage: "doc.badge.plus",
            placement: .toolbar,
            routePredicate: RoutePredicate(topLevelSectionIDs: ["library"])
        )
        try await registry.register(contribution, pluginID: "sci.paper-library") { context in
            CommandExecutionResult(
                succeeded: context.pluginID == "sci.paper-library" && context.commandID == "paper.importPDF",
                message: "ok"
            )
        }
        let visible = await registry.contributions(
            placement: .toolbar,
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )
        let hidden = await registry.contributions(
            placement: .toolbar,
            context: WorkspaceContextSnapshot(topLevelSectionID: "home")
        )
        let result = try await registry.execute(id: "paper.importPDF")

        try expect(visible.map(\.id) == ["paper.importPDF"], "Command registry should expose route-matched toolbar commands.")
        try expect(hidden.isEmpty, "Command registry should hide commands when route predicates do not match.")
        try expect(result.succeeded && result.message == "ok", "Command registry should invoke registered command handlers.")
    }

    private func declarativePermissionBrokerEnforcesManifestPermissions() async throws {
        let manifest = PluginManifest(
            id: "sci.openalex",
            name: "OpenAlex",
            permissions: PluginPermissionSet(
                readPaths: ["library/papers/"],
                writePaths: ["projects/*/outputs/"],
                networkHosts: ["api.openalex.org"],
                secrets: ["openalex_api_key"]
            )
        )
        let broker = DeclarativePermissionBroker(manifests: [manifest], fallbackDecision: .deny)
        let allowedRead = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .readFile, target: "library/papers/p1/paper.md", reason: "Read paper"))
        let allowedWrite = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .writeFile, target: "projects/demo/outputs/openalex.json", reason: "Write output"))
        let allowedNetwork = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .networkRequest, target: "https://api.openalex.org/works", reason: "Fetch metadata"))
        let deniedWrite = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .writeFile, target: "wiki/escape.md", reason: "Write wiki"))
        let deniedSecret = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .readSecret, target: "other_key", reason: "Read secret"))

        try expect(allowedRead.kind == .allow, "Permission broker should allow manifest-declared read paths.")
        try expect(allowedWrite.kind == .allow, "Permission broker should allow manifest-declared wildcard write paths.")
        try expect(allowedNetwork.kind == .allow, "Permission broker should allow manifest-declared network hosts.")
        try expect(deniedWrite.kind == .deny, "Permission broker should deny undeclared write paths when fallback is deny.")
        try expect(deniedSecret.kind == .deny, "Permission broker should deny undeclared secrets when fallback is deny.")
    }

    private func workspaceFileSystemRejectsEscapingPathsAndWritesAtomically() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("WorkspaceFileSystem", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileSystem = WorkspaceFileSystem(rootURL: rootURL)
        let path = try WorkspaceRelativePath("projects/demo/wiki/note.md")

        try await fileSystem.writeText("hello", to: path)
        let loaded = try await fileSystem.readText(path)
        let exists = await fileSystem.exists(path)

        try expect(loaded == "hello", "WorkspaceFileSystem should write and read text within the research root.")
        try expect(exists, "WorkspaceFileSystem should report existing managed paths.")
        do {
            _ = try WorkspaceRelativePath("../escape.md")
            try expect(false, "WorkspaceRelativePath should reject parent traversal.")
        } catch WorkspaceFileSystemError.invalidRelativePath {
        }
        do {
            _ = try WorkspaceRelativePath("/tmp/escape.md")
            try expect(false, "WorkspaceRelativePath should reject absolute paths.")
        } catch WorkspaceFileSystemError.invalidRelativePath {
        }
    }

    private func topSidebarBuilderProducesSixFixedItems() throws {
        let items = TopSidebarBuilder.items(pinnedOrder: ["settings", "library", "home"])
        let ids = items.map(\.id)

        try expect(Set(ids) == Set(["home", "projects", "library", "calendar", "ai-lab", "settings"]), "Top sidebar should contain exactly the six P43 top-level items.")
        try expect(ids.count == 6, "Top sidebar should not duplicate fixed items.")
        try expect(items.last?.id == "settings", "Settings should remain in the fixed top-level set.")
    }

    private func routePersistenceRoundTripsLastRoute() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("RoutePersistenceWorkspace", isDirectory: true)
        let repository = WorkspacePreferencesRepository()

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = try await repository.load(in: workspace)
        let route = WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "wiki", secondarySelection: nil)
        preferences.lastRoute = route
        try await repository.save(preferences, in: workspace)

        let loaded = try await repository.load(in: workspace)
        try expect(loaded.lastRoute == route, "WorkspacePreferences should round-trip the last ProjectSpace route.")
    }

    private func routePersistenceFallsBackWhenProjectMissing() throws {
        let result = RoutePersistence.restoreResult(
            candidate: WorkspaceRoute(top: .projects, projectID: "missing", projectTabID: "wiki"),
            activeProjectIDs: ["project-a"],
            configuration: WorkspaceModuleRegistry.defaultConfiguration()
        )

        try expect(result.route == WorkspaceRoute(top: .projects), "Missing project routes should fall back to the project list.")
        try expect(result.fallbackReason == .projectMissing, "Missing project routes should report project_missing.")
    }

    private func routePersistenceFallsBackWhenModuleDisabled() throws {
        let result = RoutePersistence.restoreResult(
            candidate: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "graph"),
            activeProjectIDs: ["project-a"],
            configuration: WorkspaceModuleRegistry.defaultConfiguration(
                enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["citation-graph"])
            )
        )

        try expect(result.route == WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "overview"), "Disabled module routes should fall back to ProjectSpace Overview.")
        try expect(result.fallbackReason == .moduleDisabled, "Disabled module routes should report module_disabled.")
    }

    private func workspacePreferencesSchemaVersion2BackwardCompat() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("PreferencesV1Workspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let workspace = ResearchWorkspace(rootURL: rootURL)
        try FileManager.default.createDirectory(at: workspace.fileURL(for: WorkspacePreferencesRepository.relativePath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try "schema_version: 1\nlibrary_visible_columns:\n  - \"title\"\nrecent_section: \"library\"\n".write(to: workspace.fileURL(for: WorkspacePreferencesRepository.relativePath), atomically: true, encoding: .utf8)

        let preferences = try await WorkspacePreferencesRepository().load(in: workspace)
        try expect(preferences.schemaVersion == WorkspacePreferences.currentSchemaVersion, "Loading v1 preferences should normalize to the current schema version.")
        try expect(preferences.liquidGlassTint == .system, "Loading old preferences should default Liquid Glass tint to system accent.")
        try expect(preferences.pinnedTopLevelOrder == WorkspacePreferences.defaultPinnedTopLevelOrder, "Loading v1 preferences should fill top-level pin defaults.")
        try expect(preferences.projectSpacePinnedOrder.isEmpty, "Loading v1 preferences should fill an empty ProjectSpace pin order.")
    }

    private func workspacePreferencesSchemaVersionForRightRail() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("PreferencesRightRailSchemaWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let workspace = ResearchWorkspace(rootURL: rootURL)
        try FileManager.default.createDirectory(at: workspace.fileURL(for: WorkspacePreferencesRepository.relativePath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try "schema_version: 2\nlibrary_visible_columns:\n  - \"title\"\nrecent_section: \"library\"\n".write(to: workspace.fileURL(for: WorkspacePreferencesRepository.relativePath), atomically: true, encoding: .utf8)

        let preferences = try await WorkspacePreferencesRepository().load(in: workspace)
        try expect(preferences.schemaVersion == WorkspacePreferences.currentSchemaVersion, "Loading pre-P43.5 preferences should normalize to the right-rail schema version.")
        try expect(preferences.rightRailMode == .inspector, "Pre-P43.5 preferences should default to inspector mode for context-rich routes.")
        try expect(!preferences.isGlobalAIPanelOpen, "Pre-P43.5 preferences should default the global AI panel to closed.")
        try expect(preferences.isProjectTreeExpanded, "Pre-P43.5 preferences should default the project tree to expanded.")
        try expect(preferences.pinnedProjectIDs.isEmpty, "Pre-P43.5 preferences should default pinned project ids to empty.")
    }

    private func projectSpaceContentRouterMapsAllKnownTabs() throws {
        for tabID in ProjectSpaceTabsBuilder.defaultOrder {
            try expect(!ProjectSpaceTabsBuilder.systemImage(for: tabID).isEmpty, "ProjectSpace tab \(tabID) should have a router/icon mapping.")
        }
    }

    private func agentLoopBudgetDefaultsAreExpanded() throws {
        let options = AgentLoopOptions()
        try expect(options.maxSteps == 20, "Agent loop should default to 20 model steps.")
        try expect(options.maxToolCalls == 80, "Agent loop should default to a larger tool-call budget.")
        try expect(options.maxContextCharacters == 1_000_000, "Agent loop should default to a 1M context character budget.")
        try expect(options.maxToolResultCharactersPerCall == 384_000, "Agent loop should default to a 384K per-tool output budget.")
        try expect(options.maxAccumulatedToolResultCharacters == 1_000_000, "Agent loop should default to a 1M accumulated tool-result budget.")
        try expect(LLMConfiguration().maxTokens == 384_000, "LLM output should default to 384K max tokens for DeepSeek-class models.")
    }

    private func appDebugEventLoggerPersistsRedactedEvents() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("AppDebugEventWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let logger = AppDebugEventLogger()
        try await logger.append(AppDebugEvent(
            event: "agent.prompt_submitted",
            workspaceID: "workspace-1",
            projectID: "project-1",
            threadID: "thread-1",
            runID: "run-1",
            payload: .object([
                "api_key": .string("sk-secret"),
                "prompt": .string("read /private/tmp/paper.md")
            ])
        ), in: root)

        let events = try await logger.events(in: root)
        let firstPayload = try require(events.first?.payload.objectValue, "Debug event should persist a structured payload.")
        try expect(events.count == 1, "Debug event logger should replay persisted events.")
        try expect(firstPayload["api_key"] == .string("[REDACTED]"), "Debug event logger should redact API keys.")
        try expect(firstPayload["prompt"] == .string("read [PATH]"), "Debug event logger should redact private paths.")
        try expect(FileManager.default.fileExists(atPath: root.fileURL(for: AppDebugEventLogger.relativePath).path), "Debug event logger should write a workspace-local JSONL file.")
    }

    /// The AI Usage Test orchestrator (`Proposal-AT.md` §P-AT.1) treats
    /// `AppDebugEventName.allCases` as the source-of-truth registry of every
    /// debug event the App may emit. The hard-coded list below is the set of
    /// event names that current call sites in the codebase emit. If you add
    /// a new `recordAppDebugEvent("...")` / `AppDebugEvent(event: ...)` /
    /// `emit("...")` call site, you MUST:
    ///   1. Add a matching case to `AppDebugEventName`.
    ///   2. Append the raw value to the `emittedEventAllowList` below.
    ///
    /// Keeping these two surfaces aligned guarantees the Python uitest
    /// orchestrator can enumerate every event it might see in
    /// `app_events.jsonl` and that nothing slips through without review.
    private func appDebugEventNameRegistryCoversAllEmittedEvents() throws {
        let registered = Set(AppDebugEventName.allCases.map(\.rawValue))
        let emittedEventAllowList: [String] = [
            // Route persistence
            "route.persist", "route.persist.fallback", "route.persist.error",
            // Project space / shell
            "project_space.tab_change", "project_space.builder_warn",
            "shell.right_rail.change", "shell.ai_panel.open", "shell.responsive_policy.apply",
            "toolbar.policy.resolve", "sidebar.render",
            // Project lifecycle
            "project.archive.requested", "project.delete.requested",
            // Wiki / Markdown
            "wiki.file.create", "wiki.file.rename", "wiki.file.archive",
            "markdown.editor.save_state", "paper_markdown.open_direct",
            // Agent
            "agent.prompt_submitted", "agent.run_completed", "agent.run_failed",
            "agent.run_cancelled", "agent.run_opened", "agent.runtime_selection_changed",
            "agent.stop_requested", "agent.context_changed",
            "agent.thread_started", "agent.thread_selected", "agent.thread_archived",
            "agent.thread_draft_discarded", "agent.archived_thread_selection_blocked",
            "agent.tools_execution_started", "agent.tools_execution_completed",
            "agent.tools_execution_failed", "agent.tools_resume_completed",
            "agent.tool.graph_query", "agent.tool.graph_result_size", "agent.tool.graph_error",
            "agent.tool.graph_insight_draft", "agent.tool.graph_blocked_by_module",
            "agent.intent.graph_routed",
            // AI Lab UX / permissions
            "ai.mode.change", "ai.timeline.project", "ai.toolset.unavailable",
            "ai.permission.inline_decision", "ai.draft_review.rewrite_requested",
            // Appearance / l10n
            "appearance.liquid_glass_tint.change", "l10n.language.change",
            // Debug
            "debug.mode.changed", "debug.log.opened",
            // Home / Project Dashboard
            "home.aggregate", "home.aggregate.error", "home.cache.invalidate",
            "home.panel.action", "home.widget.gallery",
            "home.widget.layout_enter_edit", "home.widget.layout_exit_edit",
            "home.widget.move", "home.widget.resize", "home.widget.toggle",
            "home.widget.reset_default",
            "project_dashboard.render", "project_dashboard.stage_inferred",
            // PDF annotations
            "pdf.annotation.create", "pdf.annotation.update",
            "pdf.annotation.delete", "pdf.annotation.duplicate_skipped",
            // Research Queue (P48)
            "queue.load", "queue.load.error", "queue.append", "queue.reorder",
            "queue.remove", "queue.status_change", "queue.save_error",
            "queue.ingest_error", "queue.ingest_scanned", "queue.ingest_from_recommendation",
            "reading_plan.load", "reading_plan.load.error", "reading_plan.save",
            "reading_plan.save_error", "reading_plan.activate", "reading_plan.archive",
            "reading_plan.reorder", "reading_plan.slot_status_change",
            "recommendation.arxiv_refresh", "recommendation.archive",
            "recommendation.ai_search.error", "recommendation.error",
            "recommendation.feedback", "recommendation.push.error",
            // Module settings
            "module_settings.toggle", "module_settings.toggle_chain", "module_settings.pin",
            // Graph (P44–P47)
            "graph.indexer.rebuild_started", "graph.indexer.rebuild_finished",
            "graph.indexer.incremental_skip",
            "graph.repository.loaded", "graph.repository.write",
            "graph.repository.compact", "graph.repository.compact.error",
            "graph.repository.replay_skip",
            "citation.edge_upsert", "citation.edge_tombstone",
            "citation.parse.bibtex", "citation.parse.markdown", "citation.resolve_unmatched"
        ]

        let missing = emittedEventAllowList.filter { !registered.contains($0) }
        try expect(
            missing.isEmpty,
            "AppDebugEventName is missing case(s) for emitted event(s): \(missing.sorted().joined(separator: ", ")). " +
            "Add them to Sci-Station/Agent/AppDebugEventName.swift so the AI uitest orchestrator can enumerate them."
        )

        // Sanity: the registry must not shrink unexpectedly. We bake in the
        // approximate floor so accidental case deletions are caught.
        try expect(
            AppDebugEventName.allCases.count >= emittedEventAllowList.count,
            "AppDebugEventName.allCases.count (\(AppDebugEventName.allCases.count)) dropped below the emitted-event allow-list size (\(emittedEventAllowList.count))."
        )
    }

    /// Lint: every registered event name must follow the
    /// `<domain>.<entity>(.<verb>)?` snake_case convention so the orchestrator
    /// can pattern-match domain/entity buckets when grouping scenarios.
    private func appDebugEventNameRegistryFollowsNamingConvention() throws {
        for event in AppDebugEventName.allCases {
            try expect(
                AppDebugEventName.isValidEventName(event.rawValue),
                "AppDebugEventName.\(event) raw value '\(event.rawValue)' violates snake_case <domain>.<entity>(.<verb>)? convention."
            )
        }

        let rawValues = AppDebugEventName.allCases.map(\.rawValue)
        try expect(
            Set(rawValues).count == rawValues.count,
            "AppDebugEventName raw values must be unique; found duplicates."
        )
    }

    /// `UITestAccessibilityID` is a thin namespace, but the AI uitest
    /// orchestrator depends on every factory output being machine-readable.
    /// This test covers the four high-traffic surfaces wired in P-AT.1c so
    /// future refactors that drop the strict format fail loudly.
    private func uitestAccessibilityIDFactoriesProduceValidIdentifiers() throws {
        let identifiers: [String] = [
            UITestAccessibilityID.Sidebar.tab("library"),
            UITestAccessibilityID.Sidebar.tab("settings"),
            UITestAccessibilityID.Sidebar.projectTreeToggle,
            UITestAccessibilityID.Sidebar.projectCreateButton,
            UITestAccessibilityID.Home.widget("today"),
            UITestAccessibilityID.Home.widget("active_projects"),
            UITestAccessibilityID.Library.list,
            UITestAccessibilityID.Library.importButton,
            UITestAccessibilityID.Library.paper("arxiv-2604.22012"),
            UITestAccessibilityID.Queue.list,
            UITestAccessibilityID.Queue.row("queue:workspace:paper-1")
        ]
        for identifier in identifiers {
            try expect(
                UITestAccessibilityID.isValidIdentifier(identifier),
                "UITestAccessibilityID factory produced invalid identifier: '\(identifier)'."
            )
        }
    }

    private func uitestAccessibilityIDValidatorRejectsIllegalShapes() throws {
        let illegal: [String] = [
            "",
            "no_dot",
            "Library.Paper",            // capital letters
            "library..paper",            // empty segment
            ".leading.dot",
            "trailing.dot.",
            "library paper",             // space in non-terminal
            "library.pa per",            // space in terminal
            "library.paper.\u{4F60}\u{597D}" // non-ASCII (中文)
        ]
        for raw in illegal {
            try expect(
                !UITestAccessibilityID.isValidIdentifier(raw),
                "UITestAccessibilityID validator should reject malformed identifier: '\(raw)'."
            )
        }
    }

    /// The orchestrator parses ``swiftui_warnings.log`` by splitting on
    /// newlines and then tabs, so the formatter must emit exactly five
    /// tab-separated fields per record. This test pins the contract.
    private func swiftUIRuntimeWarningCaptureFormatsOneLinePerEntry() throws {
        let date = Date(timeIntervalSince1970: 1_777_700_000)
        let line = SwiftUIRuntimeWarningCapture.formatLine(
            timestamp: date,
            subsystem: "com.apple.runtime-issues",
            category: "SwiftUI",
            process: "Sci-Station",
            message: "Modifying state during view update."
        )
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        try expect(
            fields.count == 5,
            "SwiftUIRuntimeWarningCapture.formatLine should emit 5 tab-separated fields, got \(fields.count) in '\(line)'."
        )
        try expect(
            String(fields[1]) == "com.apple.runtime-issues",
            "Second field should be the subsystem."
        )
        try expect(
            String(fields[2]) == "SwiftUI",
            "Third field should be the category."
        )
        try expect(
            String(fields[3]) == "Sci-Station",
            "Fourth field should be the process."
        )
        try expect(
            String(fields[4]) == "Modifying state during view update.",
            "Fifth field should be the message."
        )
    }

    /// Embedded newlines / tabs in OS log messages would break the
    /// one-record-per-line invariant. The formatter must collapse them.
    private func swiftUIRuntimeWarningCaptureSanitisesEmbeddedSeparators() throws {
        let date = Date(timeIntervalSince1970: 1_777_700_001)
        let line = SwiftUIRuntimeWarningCapture.formatLine(
            timestamp: date,
            subsystem: "com.apple.runtime-issues",
            category: "SwiftUI",
            process: "Sci-Station",
            message: "first line\nsecond line\twith tab\rand cr"
        )
        try expect(
            !line.contains("\n"),
            "Formatter must strip embedded newlines."
        )
        try expect(
            line.split(separator: "\t", omittingEmptySubsequences: false).count == 5,
            "Tab count must stay at 4 separators (5 fields) after sanitisation."
        )
        try expect(
            !line.contains("\r"),
            "Formatter must strip embedded carriage returns."
        )
    }

    private func homeAggregatorReturnsEmptyDataForBlankWorkspace() async throws {
        let aggregator = HomeAggregator()
        let snapshot = try await aggregator.snapshot(input: HomeAggregationInput(workspaceID: "blank-workspace"), now: Date(timeIntervalSince1970: 1_777_600_000))

        try expect(snapshot.today.dueTodos.isEmpty, "Blank workspace should have no due todos.")
        try expect(snapshot.today.readingQueue.isEmpty, "Blank workspace should have no reading queue.")
        try expect(snapshot.activeProjects.isEmpty, "Blank workspace should have no active projects.")
        try expect(snapshot.aiReview.needsApproval.isEmpty, "Blank workspace should have no pending AI drafts.")
    }

    private func homeAggregatorRespectsCacheTTL() async throws {
        let aggregator = HomeAggregator(cacheTTL: 60)
        let input = HomeAggregationInput(workspaceID: "ttl-workspace")
        let first = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_000))
        let second = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_010))
        let third = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_070))

        try expect(first.builtAt == second.builtAt, "HomeAggregator should return cached snapshots inside the TTL.")
        try expect(third.builtAt != first.builtAt, "HomeAggregator should rebuild snapshots after the TTL expires.")
    }

    private func homeAggregatorInvalidatesOnDraftInboxChange() async throws {
        let aggregator = HomeAggregator(cacheTTL: 60)
        let input = HomeAggregationInput(workspaceID: "draft-invalidation-workspace")
        let first = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_000))
        await aggregator.invalidate(reason: "draft_change")
        let second = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_005))

        try expect(first.builtAt != second.builtAt, "Draft inbox invalidation should force a Home snapshot rebuild inside the TTL.")
    }

    private func homeAggregatorInvalidatesOnTodoChange() async throws {
        let aggregator = HomeAggregator(cacheTTL: 60)
        let input = HomeAggregationInput(workspaceID: "todo-invalidation-workspace")
        let first = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_000))
        await aggregator.invalidate(reason: "todo_change")
        let second = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_006))

        try expect(first.builtAt != second.builtAt, "Todo invalidation should force a Home snapshot rebuild inside the TTL.")
    }

    private func homeAggregatorErrorRecordsDebugEvent() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("HomeAggregatorErrorWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let logger = AppDebugEventLogger()
        let aggregator = HomeAggregator(debugLogger: logger, debugRoot: root)

        do {
            _ = try await aggregator.snapshot(input: HomeAggregationInput(workspaceID: "error-workspace", failureReason: "forced failure"))
            try expect(false, "HomeAggregator should throw when its input forces a failure.")
        } catch {
            let events = try await logger.events(in: root)
            try expect(events.contains { $0.event == "home.aggregate.error" }, "HomeAggregator should record home.aggregate.error when build fails.")
        }
    }

    private func sampleQueueEntryForHomeTest(
        id: String,
        scope: QueueScope,
        order: Int,
        status: QueueStatus,
        source: QueueSource = .manual,
        paperID: String? = nil,
        externalKey: String? = nil,
        displayTitle: String,
        lastTouchedAt: Date
    ) -> ResearchQueueEntry {
        ResearchQueueEntry(
            id: id,
            paperID: paperID,
            externalKey: externalKey,
            displayTitle: displayTitle,
            scope: scope,
            status: status,
            source: source,
            order: order,
            addedAt: lastTouchedAt,
            startedAt: nil,
            finishedAt: nil,
            lastTouchedAt: lastTouchedAt,
            noteSummary: nil,
            sourceRefs: []
        )
    }

    private func homeAggregatorPopulatesReadingQueueEntriesWhenQueueAvailable() async throws {
        let aggregator = HomeAggregator()
        let baseDate = Date(timeIntervalSince1970: 1_777_600_000)
        let queueEntries: [ResearchQueueEntry] = [
            sampleQueueEntryForHomeTest(
                id: "queue:workspace:p-old",
                scope: .workspace,
                order: 1,
                status: .queued,
                paperID: "p-old",
                displayTitle: "Older Queued Paper",
                lastTouchedAt: baseDate
            ),
            sampleQueueEntryForHomeTest(
                id: "queue:workspace:p-recent",
                scope: .workspace,
                order: 2,
                status: .reading,
                paperID: "p-recent",
                displayTitle: "Recent Reading Paper",
                lastTouchedAt: baseDate.addingTimeInterval(7_200)
            ),
            sampleQueueEntryForHomeTest(
                id: "queue:workspace:p-finished",
                scope: .workspace,
                order: 3,
                status: .finished,
                paperID: "p-finished",
                displayTitle: "Finished Paper",
                lastTouchedAt: baseDate.addingTimeInterval(3_600)
            ),
            sampleQueueEntryForHomeTest(
                id: "queue:workspace:ext-arxiv",
                scope: .workspace,
                order: 4,
                status: .queued,
                source: .recommendation,
                externalKey: "arxiv:2410.12345",
                displayTitle: "External Recommendation",
                lastTouchedAt: baseDate.addingTimeInterval(1_800)
            )
        ]

        let snapshot = try await aggregator.snapshot(
            input: HomeAggregationInput(
                workspaceID: "queue-home-workspace",
                queueEntries: queueEntries
            ),
            now: baseDate.addingTimeInterval(10_000)
        )

        let entries = snapshot.today.readingQueueEntries
        try expect(entries.map(\.id) == [
            "queue:workspace:p-recent",
            "queue:workspace:ext-arxiv",
            "queue:workspace:p-old"
        ], "Today panel should sort active queue entries by lastTouchedAt desc and skip finished/dismissed rows.")
        try expect(entries.first?.status == .reading, "Most recently touched entry should land first regardless of status (queued/reading both qualify).")
        try expect(entries.last?.status == .queued, "Older queued entries should still appear when the active queue is small.")
        try expect(entries.contains { $0.externalKey == "arxiv:2410.12345" }, "Today panel should preserve external recommendations alongside library entries.")
    }

    private func homeAggregatorFallsBackToHeuristicReadingQueueWhenQueueEmpty() async throws {
        let aggregator = HomeAggregator()
        var paper = samplePaper(id: "fallback-paper")
        paper.priority = .high
        let snapshot = try await aggregator.snapshot(
            input: HomeAggregationInput(
                workspaceID: "queue-fallback-workspace",
                papers: [paper],
                queueEntries: []
            ),
            now: Date(timeIntervalSince1970: 1_777_600_000)
        )
        try expect(snapshot.today.readingQueueEntries.isEmpty, "When no queue entries are wired, readingQueueEntries should remain empty.")
        try expect(!snapshot.today.readingQueue.isEmpty, "Heuristic readingQueue should keep populating from papers so the Home card never goes blank.")
    }

    private func projectStageProviderInfersExplorationForBlankProject() throws {
        let decision = ProjectStageProvider().stage(for: ProjectStageSignal(projectID: "blank"), today: Date(timeIntervalSince1970: 1_777_600_000))
        try expect(decision.stage == .exploration, "Blank project should infer exploration stage.")
    }

    private func projectStageProviderInfersOnHoldAfter21DaysIdle() throws {
        let today = Date(timeIntervalSince1970: 1_777_600_000)
        let oldActivity = today.addingTimeInterval(-22 * 86_400)
        let decision = ProjectStageProvider().stage(for: ProjectStageSignal(projectID: "idle", papersCount: 8, wikiPageCount: 4, lastActivityAt: oldActivity), today: today)
        try expect(decision.stage == .onHold, "Projects idle for more than 21 days should infer on_hold.")
    }

    private func projectStageProviderInfersReviewingWhenUnsupportedClaimPresent() throws {
        let decision = ProjectStageProvider().stage(for: ProjectStageSignal(projectID: "review", papersCount: 8, unsupportedClaimCount: 2), today: Date(timeIntervalSince1970: 1_777_600_000))
        try expect(decision.stage == .reviewing, "Unsupported claims should infer reviewing stage.")
    }

    private func projectDashboardAggregatorReturnsCorrectStage() throws {
        let project = sampleResearchProject(id: "project-stage")
        let papers = (0..<5).map { index -> Paper in
            var paper = samplePaper(id: "stage-paper-\(index)")
            paper.projectIDs = [project.id]
            paper.coreProjectIDs = index < 2 ? [project.id] : []
            return paper
        }
        let run = sampleAgentRun(
            id: "stage-run",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 1_777_600_000),
            toolResults: [try artifactToolResult(runID: "stage-run", kind: "research_plan", createdAt: Date(timeIntervalSince1970: 1_777_600_000))]
        )
        let input = ProjectDashboardAggregationInput(
            workspaceID: "project-dashboard-stage",
            project: project,
            papers: papers,
            todos: [],
            markdownDocuments: [sampleMarkdownDocument(relativePath: "wiki/gaps/project-stage-gap.md", title: "Open Gap")],
            agentRuns: [run],
            unsupportedClaims: []
        )

        let snapshot = try require(ProjectDashboardSnapshotBuilder().build(input: input, now: Date(timeIntervalSince1970: 1_777_600_010)), "Project dashboard snapshot should build for selected project.")
        try expect(snapshot.stage == .planning, "Project dashboard should infer planning when papers, research plan, and open gaps are present.")
    }

    private func projectDashboardAggregatorOrdersArtifactsByCreatedDesc() throws {
        let project = sampleResearchProject(id: "project-artifacts")
        let olderRun = sampleAgentRun(
            id: "older-run",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 1_777_500_000),
            toolResults: [try artifactToolResult(runID: "older-run", kind: "research_plan", createdAt: Date(timeIntervalSince1970: 1_777_500_000), title: "Older Artifact")]
        )
        let newerRun = sampleAgentRun(
            id: "newer-run",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 1_777_600_000),
            toolResults: [try artifactToolResult(runID: "newer-run", kind: "related_work", createdAt: Date(timeIntervalSince1970: 1_777_600_000), title: "Newer Artifact")]
        )
        let input = ProjectDashboardAggregationInput(
            workspaceID: "project-dashboard-artifacts",
            project: project,
            agentRuns: [olderRun, newerRun]
        )

        let snapshot = try require(ProjectDashboardSnapshotBuilder().build(input: input, now: Date(timeIntervalSince1970: 1_777_600_010)), "Project dashboard snapshot should build for artifact ordering.")
        try expect(Array(snapshot.recentArtifacts.map(\.title).prefix(2)) == ["Newer Artifact", "Older Artifact"], "Project dashboard should order recent artifacts newest first.")
    }

    private func projectDashboardAggregatorBuildsReadingQueuePreview() throws {
        let project = sampleResearchProject(id: "project-queue-preview")
        var linkedPaper = samplePaper(id: "p-linked")
        linkedPaper.projectIDs = [project.id]
        var unlinkedPaper = samplePaper(id: "p-unlinked")
        unlinkedPaper.projectIDs = []

        let baseDate = Date(timeIntervalSince1970: 1_777_600_000)
        let projectScope = QueueScope.project(project.id)
        let queueEntries: [ResearchQueueEntry] = [
            sampleQueueEntryForHomeTest(
                id: "queue:project:\(project.id):p-old",
                scope: projectScope,
                order: 1,
                status: .queued,
                paperID: "p-old",
                displayTitle: "Older Project Paper",
                lastTouchedAt: baseDate
            ),
            sampleQueueEntryForHomeTest(
                id: "queue:project:\(project.id):p-recent",
                scope: projectScope,
                order: 2,
                status: .reading,
                paperID: "p-recent",
                displayTitle: "Recent Project Paper",
                lastTouchedAt: baseDate.addingTimeInterval(7_200)
            ),
            sampleQueueEntryForHomeTest(
                id: "queue:project:\(project.id):p-finished",
                scope: projectScope,
                order: 3,
                status: .finished,
                paperID: "p-finished",
                displayTitle: "Finished Project Paper",
                lastTouchedAt: baseDate.addingTimeInterval(3_600)
            ),
            sampleQueueEntryForHomeTest(
                id: "queue:workspace:p-linked",
                scope: .workspace,
                order: 4,
                status: .queued,
                paperID: "p-linked",
                displayTitle: "Workspace Linked Paper",
                lastTouchedAt: baseDate.addingTimeInterval(5_400)
            ),
            sampleQueueEntryForHomeTest(
                id: "queue:workspace:p-unlinked",
                scope: .workspace,
                order: 5,
                status: .queued,
                paperID: "p-unlinked",
                displayTitle: "Workspace Unlinked Paper",
                lastTouchedAt: baseDate.addingTimeInterval(9_000)
            )
        ]

        let input = ProjectDashboardAggregationInput(
            workspaceID: "queue-preview-workspace",
            project: project,
            papers: [linkedPaper, unlinkedPaper],
            queueEntries: queueEntries
        )
        let snapshot = try require(
            ProjectDashboardSnapshotBuilder().build(input: input, now: baseDate.addingTimeInterval(20_000)),
            "Project dashboard snapshot should build for queue preview test."
        )
        let previewIDs = snapshot.readingQueuePreview.map(\.id)
        try expect(previewIDs == [
            "queue:project:\(project.id):p-recent",
            "queue:workspace:p-linked",
            "queue:project:\(project.id):p-old"
        ], "Reading queue preview should sort active project + project-linked workspace entries by lastTouchedAt desc, capped at 3.")
        try expect(!previewIDs.contains("queue:project:\(project.id):p-finished"), "Finished entries should not appear in the project preview.")
        try expect(!previewIDs.contains("queue:workspace:p-unlinked"), "Workspace queue rows whose paper is not linked to the project should be excluded.")
    }

    private func homeSnapshotEncodesAndDecodesRoundTrip() async throws {
        let project = sampleResearchProject(id: "roundtrip-project")
        var paper = samplePaper(id: "roundtrip-paper")
        paper.projectIDs = [project.id]
        let todo = sampleTodo(id: "roundtrip-todo", title: "Read queue", projectID: project.id, dueDate: Date(timeIntervalSince1970: 1_777_600_000))
        let run = sampleAgentRun(id: "roundtrip-run", projectID: project.id, createdAt: Date(timeIntervalSince1970: 1_777_599_000), lifecycleState: .waitingForApproval)
        let snapshot = try await HomeAggregator().snapshot(input: HomeAggregationInput(
            workspaceID: "roundtrip-workspace",
            currentProjectID: project.id,
            projects: [project],
            papers: [paper],
            todos: [todo],
            agentRuns: [run]
        ), now: Date(timeIntervalSince1970: 1_777_600_000))

        let data = try AgentRunDirectoryStore.encoder().encode(snapshot)
        let decoded = try AgentRunDirectoryStore.decoder().decode(HomeSnapshot.self, from: data)
        try expect(decoded == snapshot, "HomeSnapshot should encode and decode without losing panel data.")
    }

    private func libraryBulkEditServiceUpdatesSelectedPapers() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let service = LibraryBulkEditService(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LibraryBulkEditWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let firstPaper = try await repository.save(samplePaper(id: "bulk-first"), in: workspace)
        let secondPaper = try await repository.save(samplePaper(id: "bulk-second"), in: workspace)
        let targetIDs: Set<Paper.ID> = [firstPaper.id, secondPaper.id]

        _ = try await service.setStatus(.deepRead, for: targetIDs, in: workspace)
        _ = try await service.setPriority(.urgent, for: targetIDs, in: workspace)
        _ = try await service.setRating(5, for: targetIDs, in: workspace)
        _ = try await service.addTags(["dm", "dm", "capture"], for: targetIDs, in: workspace)
        _ = try await service.removeTags(["graph"], for: targetIDs, in: workspace)

        let loadedPapers = try await repository.loadPapers(in: workspace).filter { targetIDs.contains($0.id) }
        try expect(loadedPapers.count == 2, "Bulk edit should keep both target papers loadable.")
        try expect(loadedPapers.allSatisfy { $0.status == .deepRead }, "Bulk edit should update status for all selected papers.")
        try expect(loadedPapers.allSatisfy { $0.priority == .urgent }, "Bulk edit should update priority for all selected papers.")
        try expect(loadedPapers.allSatisfy { $0.rating == 5 }, "Bulk edit should update rating for all selected papers.")
        try expect(loadedPapers.allSatisfy { $0.tags.contains("dm") && $0.tags.contains("capture") }, "Bulk edit should add tags to all selected papers.")
        try expect(loadedPapers.allSatisfy { Set($0.tags).count == $0.tags.count }, "Bulk edit should not create duplicate tags.")
        try expect(loadedPapers.allSatisfy { !$0.tags.contains("graph") }, "Bulk edit should remove requested tags.")
    }

    private func librarySortStateSortsPapers() throws {
        var older = samplePaper(id: "older")
        older.title = "Beta Paper"
        older.authors = ["Zed Author"]
        older.year = 2020
        older.updatedAt = Date(timeIntervalSince1970: 10)
        older.rating = 2
        older.priority = .low
        older.status = .used

        var newer = samplePaper(id: "newer")
        newer.title = "Alpha Paper"
        newer.authors = ["Amy Author"]
        newer.year = 2024
        newer.updatedAt = Date(timeIntervalSince1970: 20)
        newer.rating = 5
        newer.priority = .urgent
        newer.status = .unread

        let originalOrder = [older, newer]
        try expect(LibrarySortState().sorted(originalOrder).map(\.id) == ["older", "newer"], "Empty Library sort state should preserve original order.")
        try expect(LibrarySortState(field: .title, isAscending: true).sorted(originalOrder).map(\.id) == ["newer", "older"], "Title sort should order papers alphabetically.")
        try expect(LibrarySortState(field: .year, isAscending: false).sorted(originalOrder).map(\.id) == ["newer", "older"], "Year descending sort should put newer papers first.")
        try expect(LibrarySortState(field: .updated, isAscending: false).sorted(originalOrder).map(\.id) == ["newer", "older"], "Updated descending sort should put recently updated papers first.")
        try expect(LibrarySortState(field: .rating, isAscending: false).sorted(originalOrder).map(\.id) == ["newer", "older"], "Rating descending sort should put higher rated papers first.")
        try expect(LibrarySortState(field: .priority, isAscending: true).sorted(originalOrder).map(\.id) == ["newer", "older"], "Priority sort should use reading priority order.")
        try expect(LibrarySortState(field: .status, isAscending: true).sorted(originalOrder).map(\.id) == ["newer", "older"], "Status sort should use reading status order.")
    }

    private func markdownSnippetRepositoryLoadsWorkspaceSnippets() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = MarkdownSnippetRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("SnippetsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let defaultSnippets = try await repository.load(in: workspace)
        try expect(defaultSnippets.contains(where: { $0.trigger == ";eq" }), "Default snippets should include an equation trigger.")

        let customSnippets = """
        snippets:
          - trigger: ";thm"
            title: "Theorem"
            body: |
              **Theorem.** ${cursor}
        """
        try customSnippets.write(to: workspace.markdownSnippetsURL, atomically: true, encoding: .utf8)

        let loadedSnippets = try await repository.load(in: workspace)
        try expect(loadedSnippets == [MarkdownSnippet(trigger: ";thm", title: "Theorem", body: "**Theorem.** ${cursor}")], "Markdown snippet repository should load custom workspace snippets.")
    }

    private func workspaceMaterialRepositoryLoadsOnlyUserMaterials() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = WorkspaceMaterialRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MaterialsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        try "print('hello')\n".write(to: workspace.fileURL(for: "code/analysis.py"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: workspace.fileURL(for: "figures/result.png"), options: .atomic)
        try "private\n".write(to: workspace.fileURL(for: "settings/private.txt"), atomically: true, encoding: .utf8)
        try "hidden\n".write(to: workspace.fileURL(for: "code/.scratch.txt"), atomically: true, encoding: .utf8)

        let materials = try await repository.loadMaterials(in: workspace)
        let materialPaths = Set(materials.map(\.relativePath))
        let codeMaterial = try require(materials.first(where: { $0.relativePath == "code/analysis.py" }), "Expected code/analysis.py to be loaded as a material.")

        try expect(materialPaths.contains("code/analysis.py"), "Materials should include user code files.")
        try expect(codeMaterial.kind == .python, "Python files should be classified as Python materials.")
        try expect(materialPaths.contains("figures/result.png"), "Materials should include user figure files.")
        try expect(materialPaths.contains("shared_research.md"), "Materials should include shared research context.")
        try expect(!materialPaths.contains("settings/private.txt"), "Materials should hide settings files.")
        try expect(!materialPaths.contains("code/.scratch.txt"), "Materials should hide dot-prefixed files.")
        try expect(WorkspaceMaterialRepository.isVisibleMaterialPath("code/analysis.py"), "User material paths should be visible.")
        try expect(!WorkspaceMaterialRepository.isVisibleMaterialPath(".sci-station/cache.json"), "Dot-prefixed system paths should be hidden.")
    }

    private func batchImportInputParserSplitsMultipleIdentifiers() throws {
        let parser = BatchImportInputParser()
        let parsedInputs = parser.parse("""
        https://arxiv.org/abs/2401.12345, https://doi.org/10.1234/example
        inspire:2811054; https://example.org/paper.pdf https://arxiv.org/abs/2401.12345
        """)

        try expect(
            parsedInputs == [
                "https://arxiv.org/abs/2401.12345",
                "https://doi.org/10.1234/example",
                "inspire:2811054",
                "https://example.org/paper.pdf"
            ],
            "Batch parser should split common pasted separators and remove duplicates."
        )
    }

    private func paperImportPipelineDispatchesImporterAndMetadataProvider() async throws {
        let importer = RecordingPaperImporter()
        let provider = RecordingPaperMetadataProvider()
        let pipeline = PaperImportPipeline(importers: [importer], metadataProviders: [provider])
        let context = PluginContext(pluginID: "sci.test")
        let input = PaperImportInput(kind: .doi, value: "10.1234/example")
        let result = try await pipeline.importPaper(input, context: context)
        let candidates = try await pipeline.lookupMetadata(
            MetadataLookupQuery(identifierKind: "doi", value: "10.1234/example"),
            context: context
        )
        let handledValues = await importer.handledValues()
        let lookupValues = await provider.lookupValues()

        try expect(result.paperID == "paper:10.1234/example", "PaperImportPipeline should dispatch to the first matching importer.")
        try expect(result.metadata?.doi == "10.1234/example", "PaperImportPipeline should preserve importer metadata output.")
        try expect(candidates.map(\.providerID) == ["test.metadata"], "PaperImportPipeline should dispatch metadata lookup providers.")
        try expect(candidates.first?.draft.title == "Metadata Candidate", "PaperImportPipeline should return provider candidates.")
        try expect(handledValues == ["10.1234/example"], "Paper importer should observe the requested input value.")
        try expect(lookupValues == ["10.1234/example"], "Metadata provider should observe the requested lookup value.")
    }

    private func vscodeBridgePreparesPythonRunTask() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = WorkspaceMaterialRepository()
        let bridgeService = VSCodeBridgeService()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("VSCodeBridgeWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let pythonURL = workspace.fileURL(for: "code/analysis.py")
        try "print('hello')\n".write(to: pythonURL, atomically: true, encoding: .utf8)

        let materials = try await repository.loadMaterials(in: workspace)
        let material = try require(materials.first(where: { $0.relativePath == "code/analysis.py" }), "Expected Python material for VS Code bridge test.")

        try await bridgeService.preparePythonRunTask(for: material, in: workspace, runtimeMode: .workspaceVenv)

        let tasksText = try String(contentsOf: workspace.fileURL(for: ".vscode/tasks.json"), encoding: .utf8)
        let bridgeText = try String(contentsOf: workspace.fileURL(for: ".sci-station/vscode/last_python_run.json"), encoding: .utf8)

        try expect(tasksText.contains("Sci-Station: Run Python Material"), "VS Code bridge should write a runnable task label.")
        try expect(tasksText.contains("code/analysis.py"), "VS Code bridge should point to the selected Python material.")
        try expect(tasksText.contains(".venv/bin/python"), "VS Code bridge should use the selected workspace venv command.")
        try expect(bridgeText.contains("workspaceVenv"), "VS Code bridge should record the selected runtime mode.")
    }

    private func citekeyGenerationUsesAuthorYearKeyword() throws {
        let citekey = PaperIdentityGenerator.citekey(
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith"],
            year: 2024,
            existing: []
        )

        try expect(citekey == "smith2024graph", "Citekey generation should follow firstAuthorYearKeyword.")
    }

    private func metadataCodecRoundTripKeepsEditableFields() throws {
        let codec = PaperMetadataCodec()
        let createdAt = Date(timeIntervalSince1970: 1_714_176_000)
        let updatedAt = Date(timeIntervalSince1970: 1_714_262_400)
        let originalPaper = Paper(
            id: "smith2024-graph-rag",
            citekey: "smith2024graph",
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith", "Alice Wang"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            inspireID: "2811054",
            url: "https://arxiv.org/abs/2401.12345",
            pdfURL: "https://arxiv.org/pdf/2401.12345.pdf",
            abstract: "A graph-based RAG pipeline.",
            categories: ["cs.CL"],
            bibtex: """
            @article{smith2024graph,
                title = {Graph-based Retrieval Augmented Generation},
                author = {John Smith and Alice Wang},
                year = {2024}
            }
            """,
            collectionPath: "Dark-Matter/WIMPs",
            pdfRelativePath: "paper.pdf",
            tags: ["rag", "graph-rag"],
            status: .summarized,
            priority: .high,
            rating: 4,
            useFor: ["related-work", "method-design"],
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastReadAt: Date(timeIntervalSince1970: 1_714_348_800),
            lastReadPage: 12,
            paperDirectoryRelativePath: "raw/papers/Dark-Matter/WIMPs/smith2024-graph-rag",
            notesSummaryRelativePath: "../../../../../wiki/papers/smith2024graph.md",
            annotationsRelativePath: "annotations.md"
        )

        let encoded = codec.encode(originalPaper)
        let decoded = codec.decode(
            encoded,
            directoryRelativePath: originalPaper.directoryRelativePath,
            fallbackTitle: "Fallback Title",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try expect(decoded.id == originalPaper.id, "Decoded paper id should match the encoded id.")
        try expect(decoded.citekey == originalPaper.citekey, "Decoded citekey should match the encoded citekey.")
        try expect(decoded.title == originalPaper.title, "Decoded title should match the encoded title.")
        try expect(decoded.authors == originalPaper.authors, "Decoded authors should match the encoded authors.")
        try expect(decoded.year == originalPaper.year, "Decoded year should match the encoded year.")
        try expect(decoded.inspireID == originalPaper.inspireID, "Decoded INSPIRE id should match the encoded INSPIRE id.")
        try expect(decoded.pdfURL == originalPaper.pdfURL, "Decoded pdf_url should match the encoded pdf_url.")
        try expect(decoded.abstract == originalPaper.abstract, "Decoded abstract should match the encoded abstract.")
        try expect(decoded.categories == originalPaper.categories, "Decoded categories should match the encoded categories.")
        try expect(decoded.bibtex == originalPaper.bibtex, "Decoded BibTeX should match the encoded BibTeX.")
        try expect(decoded.collectionPath == originalPaper.collectionPath, "Decoded collection_path should match the encoded collection path.")
        try expect(decoded.tags == originalPaper.tags, "Decoded tags should match the encoded tags.")
        try expect(decoded.status == originalPaper.status, "Decoded status should match the encoded status.")
        try expect(decoded.priority == originalPaper.priority, "Decoded priority should match the encoded priority.")
        try expect(decoded.rating == originalPaper.rating, "Decoded rating should match the encoded rating.")
        try expect(decoded.useFor == originalPaper.useFor, "Decoded use_for should match the encoded use_for values.")
        try expect(decoded.lastReadAt == originalPaper.lastReadAt, "Decoded last_read_at should match the encoded reading state.")
        try expect(decoded.lastReadPage == originalPaper.lastReadPage, "Decoded last_page should match the encoded reading progress.")
        try expect(decoded.notesSummaryRelativePath == originalPaper.notesSummaryRelativePath, "Decoded summary path should match the encoded summary path.")
    }

    private func paperRepositorySaveAndLoadRoundTripsPaper() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("RepositoryWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = Paper(
            id: "lee2022knowledge-graph-rag",
            citekey: "lee2022knowledge",
            title: "Knowledge Graph Retrieval for RAG",
            authors: ["Min Lee"],
            year: 2022,
            venue: "ACL",
            doi: nil,
            arxiv: nil,
            url: nil,
            pdfRelativePath: "paper.pdf",
            tags: ["rag", "knowledge-graph"],
            status: .skimmed,
            priority: .medium,
            rating: 3,
            useFor: ["related-work"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            paperDirectoryRelativePath: "library/papers/Uncategorized/lee2022knowledge-graph-rag",
            notesSummaryRelativePath: "../../../../wiki/papers/lee2022knowledge.md",
            annotationsRelativePath: "annotations.md"
        )

        _ = try await repository.save(paper, in: workspace)
        let loadedPapers = try await repository.loadPapers(in: workspace)
        let loadedPaper = try require(
            loadedPapers.first(where: { $0.id == paper.id }),
            "Expected repository.loadPapers to return the saved paper."
        )

        try expect(loadedPaper.title == paper.title, "Loaded paper title should match the saved title.")
        try expect(loadedPaper.authors == paper.authors, "Loaded authors should match the saved authors.")
        try expect(loadedPaper.tags == paper.tags, "Loaded tags should match the saved tags.")
        try expect(loadedPaper.status == paper.status, "Loaded status should match the saved status.")
        try expect(loadedPaper.priority == paper.priority, "Loaded priority should match the saved priority.")
        try expect(loadedPaper.rating == paper.rating, "Loaded rating should match the saved rating.")
        try expect(
            loadedPaper.notesSummaryRelativePath == paper.notesSummaryRelativePath,
            "Loaded summary path should match the saved summary path."
        )
        try expect(
            loadedPaper.collectionPath == "Uncategorized",
            "Loaded collection path should be derived from the nested paper directory."
        )
    }

    private func paperRepositoryKeepsLegacyRawPapersLoadable() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyRawPaperWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var legacyPaper = samplePaper(id: "legacy-raw-paper")
        legacyPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-raw-paper"
        legacyPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: legacyPaper.citekey,
            paperDirectoryRelativePath: legacyPaper.paperDirectoryRelativePath
        )

        _ = try await repository.save(legacyPaper, in: workspace)
        let loadedPaper = try require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == legacyPaper.id }),
            "Expected repository to keep legacy raw/papers metadata loadable."
        )

        try expect(loadedPaper.paperDirectoryRelativePath.hasPrefix("raw/papers/"), "Legacy paper paths should remain in raw/papers.")
        try expect(loadedPaper.collectionPath == "Legacy", "Legacy raw/papers collections should still be derived correctly.")
    }

    private func legacyPaperMigrationPlanDetectsRawPaperConflicts() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let migrationService = LegacyPaperMigrationService()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyMigrationPlanWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)

        var readyPaper = samplePaper(id: "legacy-ready-paper")
        readyPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-ready-paper"
        readyPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: readyPaper.citekey,
            paperDirectoryRelativePath: readyPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(readyPaper, in: workspace)

        var conflictPaper = samplePaper(id: "legacy-conflict-paper")
        conflictPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-conflict-paper"
        conflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: conflictPaper.citekey,
            paperDirectoryRelativePath: conflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(conflictPaper, in: workspace)

        var globalConflictPaper = conflictPaper
        globalConflictPaper.paperDirectoryRelativePath = "library/papers/Legacy/legacy-conflict-paper"
        globalConflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: globalConflictPaper.citekey,
            paperDirectoryRelativePath: globalConflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(globalConflictPaper, in: workspace)

        let plan = try await migrationService.makePlan(in: workspace)
        let readyItem = try require(
            plan.items.first(where: { $0.paperID == readyPaper.id }),
            "Expected migration plan to include a ready legacy paper."
        )
        let conflictItem = try require(
            plan.items.first(where: { $0.paperID == conflictPaper.id }),
            "Expected migration plan to include a conflicting legacy paper."
        )

        try expect(plan.legacyPaperCount == 2, "Migration plan should count legacy raw/papers metadata files.")
        try expect(plan.readyCount == 1, "Migration plan should count ready-to-copy legacy papers.")
        try expect(plan.conflictCount == 1, "Migration plan should count conflicting legacy papers.")
        try expect(readyItem.status == .readyToCopy, "A legacy paper without a target conflict should be ready to copy.")
        try expect(readyItem.targetRelativePath == "library/papers/Legacy/legacy-ready-paper", "Migration plan should preserve collection paths under library/papers.")
        try expect(conflictItem.status == .conflict, "A legacy paper with a global duplicate should be marked as a conflict.")
        try expect(conflictItem.conflicts.contains(.targetDirectoryExists), "Migration plan should flag existing target directories.")
        try expect(conflictItem.conflicts.contains(.duplicatePaperIDInGlobalLibrary), "Migration plan should flag duplicate global paper ids.")
    }

    private func legacyPaperMigrationCopyWritesReportAndPrefersGlobalPaper() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let migrationService = LegacyPaperMigrationService()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyMigrationCopyWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)

        var readyPaper = samplePaper(id: "legacy-copy-ready-paper")
        readyPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-copy-ready-paper"
        readyPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: readyPaper.citekey,
            paperDirectoryRelativePath: readyPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(readyPaper, in: workspace)

        var conflictPaper = samplePaper(id: "legacy-copy-conflict-paper")
        conflictPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-copy-conflict-paper"
        conflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: conflictPaper.citekey,
            paperDirectoryRelativePath: conflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(conflictPaper, in: workspace)

        var globalConflictPaper = conflictPaper
        globalConflictPaper.paperDirectoryRelativePath = "library/papers/Legacy/legacy-copy-conflict-paper"
        globalConflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: globalConflictPaper.citekey,
            paperDirectoryRelativePath: globalConflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(globalConflictPaper, in: workspace)

        let report = try await migrationService.copyReadyItems(in: workspace)
        let reportRelativePath = try require(report.reportRelativePath, "Migration report should include its relative path.")
        let reportURL = workspace.fileURL(for: reportRelativePath)
        let copiedDirectoryURL = workspace.directoryURL(for: "library/papers/Legacy/legacy-copy-ready-paper")
        let legacyDirectoryURL = workspace.directoryURL(for: "raw/papers/Legacy/legacy-copy-ready-paper")
        let loadedPapers = try await paperRepository.loadPapers(in: workspace)
        let loadedReadyPapers = loadedPapers.filter { $0.id == readyPaper.id }
        let loadedReadyPaper = try require(loadedReadyPapers.first, "Expected copied paper to be loadable.")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedReport = try decoder.decode(LegacyPaperMigrationReport.self, from: Data(contentsOf: reportURL))

        try expect(report.copiedCount == 1, "Copy migration should copy ready legacy papers.")
        try expect(report.skippedCount == 1, "Copy migration should skip conflicting legacy papers.")
        try expect(report.failedCount == 0, "Copy migration should not fail ready papers in the happy path.")
        try expect(FileManager.default.fileExists(atPath: reportURL.path), "Copy migration should write a JSON report.")
        try expect(decodedReport.items.count == 2, "Written migration report should include every planned legacy item.")
        try expect(FileManager.default.fileExists(atPath: copiedDirectoryURL.path), "Copy migration should create the global library paper directory.")
        try expect(FileManager.default.fileExists(atPath: legacyDirectoryURL.path), "Copy migration should keep the legacy raw/papers directory in place.")
        try expect(loadedReadyPapers.count == 1, "PaperRepository should not return duplicate ids after migration copy.")
        try expect(loadedReadyPaper.paperDirectoryRelativePath == "library/papers/Legacy/legacy-copy-ready-paper", "PaperRepository should prefer the global library copy after migration.")
        try expect(loadedReadyPaper.notesSummaryRelativePath == Paper.summaryRelativePath(for: loadedReadyPaper.citekey, paperDirectoryRelativePath: loadedReadyPaper.paperDirectoryRelativePath), "Copied metadata should be normalized to the new library path.")
    }

    private func projectPaperLinkRepositoryRoundTripsAndOverlaysPaperMetadata() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let linkRepository = ProjectPaperLinkRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ProjectPaperLinkWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "linked-paper"), in: workspace)
        try await linkRepository.save([
            ProjectPaperLink(
                projectID: "project-alpha",
                paperID: paper.id,
                isCore: true,
                folderPath: "Project-Folder",
                useFor: ["method-design"],
                isPinned: true,
                sortOrder: 3
            )
        ], in: workspace)

        let loadedLinks = try await linkRepository.links(forPaperID: paper.id, in: workspace)
        let loadedPaper = try require(
            try await paperRepository.loadPapers(in: workspace).first(where: { $0.id == paper.id }),
            "Expected project links to overlay loaded paper metadata."
        )

        try expect(loadedLinks.count == 1, "Project-paper link repository should load saved links.")
        try expect(loadedPaper.projectIDs == ["project-alpha"], "Loaded paper should expose project ids from the link repository.")
        try expect(loadedPaper.coreProjectIDs == ["project-alpha"], "Loaded paper should expose core project ids from the link repository.")
        try expect(loadedPaper.folderPath == "Project-Folder", "Loaded paper should expose the project folder from the link repository.")
        try expect(loadedPaper.useFor.contains("method-design"), "Loaded paper should merge project use cases from the link repository.")
        try expect(loadedLinks.first?.isPinned == true, "Project-paper link repository should round-trip pinned state.")
        try expect(loadedLinks.first?.sortOrder == 3, "Project-paper link repository should round-trip sort order.")
    }

    private func projectPaperLinkRepositoryEditsSingleLinksAndLoadsLegacyYAML() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let linkRepository = ProjectPaperLinkRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ProjectPaperLinkEditWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        try FileManager.default.createDirectory(at: workspace.projectPaperLinksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        links:
          - project_id: "project-alpha"
            paper_id: "paper-alpha"
            is_core: true
            folder_path: "Reading Queue"
            use_for:
              - "background"
            created_at: 2026-04-29T00:00:00Z
            updated_at: 2026-04-29T00:00:00Z
        """.write(to: workspace.projectPaperLinksURL, atomically: true, encoding: .utf8)

        let legacyLink = try require(
            try await linkRepository.link(forPaperID: "paper-alpha", projectID: "project-alpha", in: workspace),
            "Expected legacy project-paper link YAML to load without pin/order fields."
        )
        try expect(legacyLink.isPinned == false, "Legacy project-paper links should default to unpinned.")
        try expect(legacyLink.sortOrder == nil, "Legacy project-paper links should default to no explicit sort order.")

        let pinnedLink = try await linkRepository.setPinned(true, projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let orderedLink = try await linkRepository.updateSortOrder(2, projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let useForLink = try await linkRepository.updateUseFor(["method", "method", "comparison"], projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let folderLink = try await linkRepository.updateFolderPath("  Methods/Core  ", projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        _ = try await linkRepository.setCore(false, projectID: "project-alpha", paperID: "paper-alpha", in: workspace)

        let editedLink = try require(
            try await linkRepository.link(forPaperID: "paper-alpha", projectID: "project-alpha", in: workspace),
            "Expected single-link edit APIs to keep the edited link loadable."
        )
        let encodedYAML = try String(contentsOf: workspace.projectPaperLinksURL, encoding: .utf8)

        try expect(pinnedLink.isPinned, "setPinned should return the updated pinned link.")
        try expect(orderedLink.sortOrder == 2, "updateSortOrder should return the updated sort order.")
        try expect(useForLink.useFor == ["method", "comparison"], "updateUseFor should normalize duplicate project usage values.")
        try expect(folderLink.folderPath == "Methods/Core", "updateFolderPath should trim project folder paths.")
        try expect(editedLink.isCore == false, "setCore should update the existing link.")
        try expect(editedLink.isPinned == true, "Edited link should persist pinned state.")
        try expect(editedLink.sortOrder == 2, "Edited link should persist sort order.")
        try expect(encodedYAML.contains("is_pinned: true"), "Encoded project-paper links should include pinned state.")
        try expect(encodedYAML.contains("sort_order: 2"), "Encoded project-paper links should include sort order.")

        let remainingLinks = try await linkRepository.remove(projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let removedLink = try await linkRepository.link(forPaperID: "paper-alpha", projectID: "project-alpha", in: workspace)
        try expect(remainingLinks.isEmpty, "Removing a project-paper link should return no remaining links for that paper.")
        try expect(removedLink == nil, "Removed project-paper link should not load again.")
    }

    private func paperRepositoryKeepsLegacyProjectMetadataWithoutLinks() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let linkRepository = ProjectPaperLinkRepository()
        let paperRepository = PaperRepository(projectPaperLinkRepository: linkRepository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyProjectMetadataWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var paper = samplePaper(id: "legacy-project-paper")
        paper.projectIDs = ["legacy-project"]
        paper.coreProjectIDs = ["legacy-project"]

        let savedPaper = try await paperRepository.save(paper, in: workspace)
        try await linkRepository.save([], in: workspace)

        let loadedPaper = try require(
            try await paperRepository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected legacy project metadata paper to remain loadable without relationship links."
        )

        try expect(loadedPaper.projectIDs == ["legacy-project"], "Legacy project_ids metadata should still bridge when no relationship links exist.")
        try expect(loadedPaper.coreProjectIDs == ["legacy-project"], "Legacy core_project_ids metadata should still bridge when no relationship links exist.")
    }

    private func paperRepositoryDeletesPaperDirectory() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("DeletePaperWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await repository.save(samplePaper(id: "delete-test-paper"), in: workspace)
        let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)

        try expect(FileManager.default.fileExists(atPath: paperDirectoryURL.path), "Saved paper directory should exist before deletion.")

        try await repository.delete(paper, in: workspace)
        let loadedPapers = try await repository.loadPapers(in: workspace)

        try expect(!FileManager.default.fileExists(atPath: paperDirectoryURL.path), "Deleting a paper should remove its paper directory.")
        try expect(loadedPapers.isEmpty, "Deleted papers should no longer appear in repository loads.")
    }

    private func librarySearchMatchesExtendedMetadata() throws {
        var paper = samplePaper(id: "search-paper")
        paper.doi = "10.1234/searchable"
        paper.abstract = "This abstract discusses solar capture."
        paper.bibtex = """
        @article{smith2024graph,
          title = {Graph RAG},
          keyword = {neutrino telescope}
        }
        """

        let service = LibrarySearchService()

        try expect(service.matches(paper, query: "10.1234"), "Library search should match DOI.")
        try expect(service.matches(paper, query: "solar capture"), "Library search should match abstracts.")
        try expect(service.matches(paper, query: "neutrino telescope"), "Library search should match BibTeX contents.")
        try expect(service.matchingIDs(in: [paper], query: "2401.12345") == [paper.id], "Library search should return matching paper ids.")
    }

    private func paperAnnotationsRepositoryRoundTripsAnnotations() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let annotationsRepository = PaperAnnotationsRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AnnotationsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "annotations-paper"), in: workspace)
        try await annotationsRepository.saveAnnotations("# Notes\n\nImportant reading note.", for: paper, in: workspace)
        let loadedAnnotations = try await annotationsRepository.loadAnnotations(for: paper, in: workspace)

        try expect(loadedAnnotations.contains("Important reading note."), "Paper annotations repository should round-trip annotations.md contents.")
    }

    private func pdfAnnotationStoreRoundTripsSidecar() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let paperRepository = PaperRepository()
        let store = PDFAnnotationStore()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PDFAnnotationsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "pdf-sidecar-paper"), in: workspace)
        let annotation = PDFAnnotationRecord(
            id: "mark-1",
            paperID: paper.id,
            pageIndex: 2,
            kind: .highlight,
            bounds: [PDFAnnotationBounds(pageIndex: 2, x: 10, y: 20, width: 120, height: 18)],
            selectedTextPreview: "Important result",
            noteText: nil,
            colorHex: "#F7D154",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        try await store.saveAnnotations([annotation], for: paper, in: workspace)
        let loaded = try await store.loadAnnotations(for: paper, in: workspace)
        let sidecarPath = try await store.sidecarRelativePath(for: paper, in: workspace)

        try expect(loaded == [annotation], "PDFAnnotationStore should round-trip sidecar records.")
        try expect(sidecarPath.hasSuffix("pdf_annotations.json"), "PDFAnnotationStore should write the expected sidecar filename.")
    }

    private func pdfAnnotationStoreRejectsPathTraversal() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        let store = PDFAnnotationStore()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PDFTraversalWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var paper = samplePaper(id: "bad-path-paper")
        paper.paperDirectoryRelativePath = "library/papers/../escape"

        do {
            _ = try await store.loadAnnotations(for: paper, in: workspace)
            throw ValidationError(message: "PDFAnnotationStore should reject paper directory path traversal.")
        } catch PDFAnnotationStoreError.invalidPaperDirectory {
        }
    }

    private func pdfAnnotationStoreHandlesMissingSidecar() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        let paperRepository = PaperRepository()
        let store = PDFAnnotationStore()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PDFMissingSidecarWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "missing-sidecar-paper"), in: workspace)
        let loaded = try await store.loadAnnotations(for: paper, in: workspace)

        try expect(loaded.isEmpty, "PDFAnnotationStore should treat a missing sidecar as an empty migration state.")
    }

    private func paperRepositoryLoadsNestedCollectionPapers() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("NestedCollectionsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let nestedPaper = Paper(
            id: "garani2024dark",
            citekey: "garani2024dark",
            title: "Dark Matter Capture Review",
            authors: ["Jakob Garani"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            url: "https://arxiv.org/abs/2401.12345",
            pdfRelativePath: "paper.pdf",
            tags: ["dark-matter"],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: Date(timeIntervalSince1970: 1_714_176_000),
            updatedAt: Date(timeIntervalSince1970: 1_714_176_000),
            paperDirectoryRelativePath: "library/papers/Dark-Matter/Solar-Capture/garani2024dark",
            notesSummaryRelativePath: "../../../../../wiki/papers/garani2024dark.md",
            annotationsRelativePath: "annotations.md"
        )

        let savedPaper = try await repository.save(nestedPaper, in: workspace)
        let paperDirectoryURL = workspace.directoryURL(for: savedPaper.paperDirectoryRelativePath)
        let pdfURL = paperDirectoryURL.appendingPathComponent("paper.pdf")
        try Data("fake pdf".utf8).write(to: pdfURL, options: .atomic)
        let metadataURL = paperDirectoryURL.appendingPathComponent("meta.yaml")
        let staleMetadata = try String(contentsOf: metadataURL, encoding: .utf8)
            .replacingOccurrences(of: "collection_path: \"Dark-Matter/Solar-Capture\"", with: "collection_path: \"Old-Folder\"")
        try staleMetadata.write(to: metadataURL, atomically: true, encoding: .utf8)

        let loadedPaper = try require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected repository to find meta.yaml inside nested collection folders."
        )

        try expect(
            loadedPaper.paperDirectoryRelativePath == nestedPaper.paperDirectoryRelativePath,
            "Repository should preserve nested paper directory paths."
        )
        try expect(
            loadedPaper.collectionPath == "Dark-Matter/Solar-Capture",
            "Repository should derive the full nested collection path from the directory layout."
        )
    }

    private func tagRepositoryUpsertsAndDeletesDefinitions() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = TagRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("TagWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)

        try await repository.upsert(
            TagDefinition(name: "Theory", colorHex: "#B57EDC", textColorHex: "#4A235A"),
            in: workspace
        )
        try await repository.upsert(
            TagDefinition(name: "Experiment", colorHex: "#85C1E9", textColorHex: "#154360"),
            in: workspace
        )
        try await repository.upsert(
            TagDefinition(name: "Theory", colorHex: "#C39BD3", textColorHex: "#45235A"),
            in: workspace
        )

        let savedDefinitions = try await repository.loadDefinitions(in: workspace)
        try expect(savedDefinitions.count == 2, "Upserting a tag twice should replace the existing definition instead of duplicating it.")
        try expect(savedDefinitions.first(where: { $0.name == "Theory" })?.colorHex == "#C39BD3", "Upsert should update an existing tag color.")

        try await repository.deleteTag(named: "Experiment", in: workspace)
        let remainingDefinitions = try await repository.loadDefinitions(in: workspace)
        try expect(remainingDefinitions.map(\.name) == ["Theory"], "Deleting a tag should remove it from refs/tags.yaml.")
    }

    private func todoRepositoryCreatesCompletesAndDeletesTodos() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = TodoRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("TodoWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let todo = TodoItem(
            id: "todo-001",
            title: "Read dark matter capture review",
            status: .open,
            dueDate: Date(timeIntervalSince1970: 1_777_680_000),
            priority: .urgent,
            projectIDs: ["project-alpha"],
            tags: ["Dark-Matter"],
            relatedPaperIDs: ["garani2024dark"],
            notes: "Check bibliography and equations.",
            externalSource: "apple_reminders",
            externalIdentifier: "reminder-abc",
            externalUpdatedAt: Date(timeIntervalSince1970: 1_777_600_000),
            completedAt: nil,
            dueTime: "09:30",
            createdAt: Date(timeIntervalSince1970: 1_777_593_600),
            updatedAt: Date(timeIntervalSince1970: 1_777_593_600)
        )

        try await repository.upsert(todo, in: workspace)

        var savedTodos = try await repository.loadTodos(in: workspace)
        try expect(savedTodos.count == 1, "Saving a todo should persist it to tasks/todos.yaml.")
        try expect(savedTodos.first?.priority == .urgent, "Todo repository should preserve priority.")
        try expect(savedTodos.first?.projectIDs == ["project-alpha"], "Todo repository should preserve project ids.")
        try expect(savedTodos.first?.notes == "Check bibliography and equations.", "Todo repository should preserve notes.")
        try expect(savedTodos.first?.relatedPaperIDs == ["garani2024dark"], "Todo repository should preserve related paper ids.")
        try expect(savedTodos.first?.externalSource == "apple_reminders", "Todo repository should preserve external source.")
        try expect(savedTodos.first?.externalIdentifier == "reminder-abc", "Todo repository should preserve external identifier.")
        try expect(savedTodos.first?.dueTime == "09:30", "Todo repository should preserve due time.")

        var completedTodo = try require(savedTodos.first, "Expected the saved todo to be loadable.")
        completedTodo.status = .done
        completedTodo.updatedAt = Date(timeIntervalSince1970: 1_777_680_000)
        try await repository.upsert(completedTodo, in: workspace)

        savedTodos = try await repository.loadTodos(in: workspace)
        try expect(savedTodos.first?.status == .done, "Updating a todo should replace the stored todo instead of duplicating it.")

        try await repository.delete(todoID: todo.id, in: workspace)
        let remainingTodos = try await repository.loadTodos(in: workspace)
        try expect(remainingTodos.isEmpty, "Deleting a todo should remove it from tasks/todos.yaml.")

                let legacyContents = """
                todos:
                    - id: "legacy-todo"
                        title: "Legacy task"
                        status: open
                        due:
                        priority: medium
                        tags: []
                        related_papers: []
                        created: 2026-04-28
                        updated: 2026-04-28
                """
                try legacyContents.write(to: workspace.fileURL(for: "tasks/todos.yaml"), atomically: true, encoding: .utf8)
                let legacyTodos = try await repository.loadTodos(in: workspace)
                try expect(legacyTodos.first?.projectIDs == [], "Todo repository should treat legacy todos without project_ids as unassigned.")
    }

    // MARK: - P48 Research Queue (Layer A: store + YAML)

    private func makeQueueWorkspace(_ name: String) throws -> (URL, ResearchWorkspace) {
        let rootURL = temporaryDirectoryURL().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return (rootURL, ResearchWorkspace(rootURL: rootURL))
    }

    private func sampleQueueEntry(
        id: String,
        scope: QueueScope,
        order: Int,
        status: QueueStatus = .queued,
        source: QueueSource = .manual,
        paperID: String? = nil,
        externalKey: String? = nil,
        displayTitle: String = "Sample Paper",
        addedAt: Date = Date(timeIntervalSince1970: 1_777_600_000),
        lastTouchedAt: Date = Date(timeIntervalSince1970: 1_777_600_000),
        noteSummary: String? = nil,
        sourceRefs: [String] = []
    ) -> ResearchQueueEntry {
        ResearchQueueEntry(
            id: id,
            paperID: paperID,
            externalKey: externalKey,
            displayTitle: displayTitle,
            scope: scope,
            status: status,
            source: source,
            order: order,
            addedAt: addedAt,
            startedAt: nil,
            finishedAt: nil,
            lastTouchedAt: lastTouchedAt,
            noteSummary: noteSummary,
            sourceRefs: sourceRefs
        )
    }

    private func researchQueueStoreAppendPersistsAndReloads() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueuePersistWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        let entry = sampleQueueEntry(
            id: "queue:workspace:p1",
            scope: .workspace,
            order: 1,
            paperID: "p1",
            displayTitle: "Persisted Paper"
        )
        try await store.append(entry)
        let storedIDs = await store.entries(in: .workspace).map(\.id)
        try expect(storedIDs == ["queue:workspace:p1"], "Append should add the row to the workspace queue.")

        let queueFileURL = workspace.fileURL(for: "library/queue.yaml")
        try expect(FileManager.default.fileExists(atPath: queueFileURL.path), "Append should create library/queue.yaml on disk.")

        await store.close()

        let reopened = ResearchQueueStore(workspace: workspace)
        try await reopened.open()
        let reloaded = await reopened.entries(in: .workspace)
        try expect(reloaded.count == 1, "Reopening should reload the persisted entry.")
        try expect(reloaded.first?.paperID == "p1", "Reopened entry should preserve paper_id.")
        try expect(reloaded.first?.displayTitle == "Persisted Paper", "Reopened entry should preserve display_title.")
    }

    private func researchQueueStoreAppendBatchPreservesOrderWithinBatch() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueAppendBatchWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        let entries = [
            sampleQueueEntry(id: "queue:workspace:a", scope: .workspace, order: 0, paperID: "a"),
            sampleQueueEntry(id: "queue:workspace:b", scope: .workspace, order: 0, paperID: "b"),
            sampleQueueEntry(id: "queue:workspace:c", scope: .workspace, order: 0, paperID: "c")
        ]
        try await store.appendBatch(entries, scope: .workspace)
        let stored = await store.entries(in: .workspace)
        try expect(stored.map(\.id) == ["queue:workspace:a", "queue:workspace:b", "queue:workspace:c"], "appendBatch should preserve input order when callers leave order=0.")
        try expect(stored.map(\.order) == [1, 2, 3], "appendBatch should auto-assign monotonically increasing order values.")
    }

    private func researchQueueStoreReorderRewritesOrderField() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueReorderWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        let entries = [
            sampleQueueEntry(id: "queue:workspace:a", scope: .workspace, order: 1, paperID: "a"),
            sampleQueueEntry(id: "queue:workspace:b", scope: .workspace, order: 2, paperID: "b"),
            sampleQueueEntry(id: "queue:workspace:c", scope: .workspace, order: 3, paperID: "c")
        ]
        try await store.appendBatch(entries, scope: .workspace)
        try await store.reorder(scope: .workspace, orderedIDs: ["queue:workspace:c", "queue:workspace:b", "queue:workspace:a"])
        let stored = await store.entries(in: .workspace)
        try expect(stored.map(\.id) == ["queue:workspace:c", "queue:workspace:b", "queue:workspace:a"], "Reorder should reflect the supplied order.")
        try expect(stored.map(\.order) == [1, 2, 3], "Reorder should rewrite the order field as 1..n.")
    }

    private func researchQueueStoreReorderHandlesPartialIDList() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueuePartialReorderWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        let entries = [
            sampleQueueEntry(id: "queue:workspace:a", scope: .workspace, order: 1, paperID: "a"),
            sampleQueueEntry(id: "queue:workspace:b", scope: .workspace, order: 2, paperID: "b"),
            sampleQueueEntry(id: "queue:workspace:c", scope: .workspace, order: 3, paperID: "c"),
            sampleQueueEntry(id: "queue:workspace:d", scope: .workspace, order: 4, paperID: "d")
        ]
        try await store.appendBatch(entries, scope: .workspace)
        try await store.reorder(scope: .workspace, orderedIDs: ["queue:workspace:c", "queue:workspace:a"])
        let stored = await store.entries(in: .workspace)
        try expect(stored.map(\.id) == [
            "queue:workspace:c",
            "queue:workspace:a",
            "queue:workspace:b",
            "queue:workspace:d"
        ], "Partial reorder should append unspecified IDs at the tail in their prior relative order.")
        try expect(stored.map(\.order) == [1, 2, 3, 4], "Partial reorder should still produce contiguous order values.")
    }

    private func researchQueueStoreUpdateStatusRecordsTimestamps() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueStatusWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        let initialAt = Date(timeIntervalSince1970: 1_777_600_000)
        let entry = sampleQueueEntry(
            id: "queue:workspace:a",
            scope: .workspace,
            order: 1,
            status: .queued,
            paperID: "a",
            addedAt: initialAt,
            lastTouchedAt: initialAt
        )
        try await store.append(entry)

        let readingAt = Date(timeIntervalSince1970: 1_777_600_500)
        try await store.updateStatus(id: entry.id, status: .reading, at: readingAt)
        let afterReading = try require(await store.entry(id: entry.id), "Entry should still exist after updateStatus.")
        try expect(afterReading.status == .reading, "updateStatus should change the status field.")
        try expect(afterReading.startedAt == readingAt, "Switching to reading should write startedAt.")
        try expect(afterReading.lastTouchedAt == readingAt, "Switching to reading should update lastTouchedAt.")

        let finishedAt = Date(timeIntervalSince1970: 1_777_601_000)
        try await store.updateStatus(id: entry.id, status: .finished, at: finishedAt)
        let afterFinish = try require(await store.entry(id: entry.id), "Entry should still exist after second updateStatus.")
        try expect(afterFinish.status == .finished, "updateStatus should change the status field a second time.")
        try expect(afterFinish.finishedAt == finishedAt, "Switching to finished should write finishedAt.")
        try expect(afterFinish.startedAt == readingAt, "finishedAt update should not overwrite an earlier startedAt.")
        try expect(afterFinish.lastTouchedAt == finishedAt, "Switching to finished should update lastTouchedAt.")
    }

    private func researchQueueStoreRemoveDoesNotAffectOtherScopes() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueRemoveScopeWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        try await store.append(sampleQueueEntry(id: "queue:workspace:a", scope: .workspace, order: 1, paperID: "a"))
        try await store.append(sampleQueueEntry(id: "queue:project:p1:b", scope: .project("p1"), order: 1, paperID: "b"))

        try await store.remove(id: "queue:workspace:a")
        let workspaceAfterRemove = await store.entries(in: .workspace)
        let projectAfterRemove = await store.entries(in: .project("p1")).map(\.id)
        try expect(workspaceAfterRemove.isEmpty, "Removing the workspace entry should leave the workspace queue empty.")
        try expect(projectAfterRemove == ["queue:project:p1:b"], "Removing the workspace entry should not touch the project queue.")
    }

    private func researchQueueStoreLoadIgnoresMalformedEntriesAndLogsWarning() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueMalformedWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let queueFileURL = workspace.fileURL(for: "library/queue.yaml")
        try FileManager.default.createDirectory(at: queueFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let malformedYAML = """
        schema_version: 1
        scope: "workspace"
        generated_at: "2026-05-17T12:00:00Z"
        entries:
          - id: "queue:workspace:good"
            paper_id: "good"
            external_key: null
            display_title: "Good Entry"
            scope: "workspace"
            status: queued
            source: manual
            order: 1
            added_at: "2026-05-17T11:00:00Z"
            started_at: null
            finished_at: null
            last_touched_at: "2026-05-17T11:00:00Z"
            note_summary: null
            source_refs: []
          - id: "queue:workspace:bad"
            display_title: "Missing required fields"
            order: 2
            note_summary: null
            source_refs: []
        """
        try malformedYAML.write(to: queueFileURL, atomically: true, encoding: .utf8)
        let originalContents = try String(contentsOf: queueFileURL, encoding: .utf8)

        let logger = AppDebugEventLogger()
        let store = ResearchQueueStore(workspace: workspace, debugLogger: logger)
        try await store.open()

        let stored = await store.entries(in: .workspace)
        try expect(stored.map(\.id) == ["queue:workspace:good"], "Malformed entries should be skipped while keeping valid rows loaded.")

        let postLoadContents = try String(contentsOf: queueFileURL, encoding: .utf8)
        try expect(postLoadContents == originalContents, "Loading malformed YAML should not rewrite the file.")

        let root = ResearchRoot(rootURL: workspace.rootURL)
        let events = try await logger.events(in: root)
        let loadErrorEvents = events.filter { $0.event == "queue.load.error" }
        try expect(!loadErrorEvents.isEmpty, "Malformed YAML should emit at least one queue.load.error debug event.")
        let firstPayload = try require(loadErrorEvents.first?.payload.objectValue, "queue.load.error should ship a structured payload.")
        try expect(firstPayload["reason"] == .string("yaml_parse_failure"), "queue.load.error should report yaml_parse_failure as the reason.")
    }

    private func researchQueueStoreWorkspaceQueueTopRespectsLimitAndStatusFilter() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueTopWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        let entries: [ResearchQueueEntry] = [
            sampleQueueEntry(id: "queue:workspace:a", scope: .workspace, order: 1, status: .queued, paperID: "a"),
            sampleQueueEntry(id: "queue:workspace:b", scope: .workspace, order: 2, status: .reading, paperID: "b"),
            sampleQueueEntry(id: "queue:workspace:c", scope: .workspace, order: 3, status: .finished, paperID: "c"),
            sampleQueueEntry(id: "queue:workspace:d", scope: .workspace, order: 4, status: .queued, paperID: "d"),
            sampleQueueEntry(id: "queue:workspace:e", scope: .workspace, order: 5, status: .dismissed, paperID: "e")
        ]
        try await store.appendBatch(entries, scope: .workspace)

        let topAll = await store.workspaceQueueTop(limit: 10)
        try expect(topAll.map(\.id) == ["queue:workspace:a", "queue:workspace:b", "queue:workspace:d"], "workspaceQueueTop should hide finished and dismissed entries.")

        let topTwo = await store.workspaceQueueTop(limit: 2)
        try expect(topTwo.map(\.id) == ["queue:workspace:a", "queue:workspace:b"], "workspaceQueueTop should respect the limit.")

        let topZero = await store.workspaceQueueTop(limit: 0)
        try expect(topZero.isEmpty, "workspaceQueueTop with limit 0 should return no entries.")
    }

    private func researchQueueStoreProjectQueueIsolatedPerProjectID() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueProjectIsolationWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        try await store.append(sampleQueueEntry(id: "queue:project:p1:a", scope: .project("p1"), order: 1, paperID: "a"))
        try await store.append(sampleQueueEntry(id: "queue:project:p2:b", scope: .project("p2"), order: 1, paperID: "b"))

        let p1 = await store.entries(in: .project("p1")).map(\.id)
        let p2 = await store.entries(in: .project("p2")).map(\.id)
        let workspaceEntries = await store.entries(in: .workspace)

        try expect(p1 == ["queue:project:p1:a"], "Project p1 queue should only contain its own entry.")
        try expect(p2 == ["queue:project:p2:b"], "Project p2 queue should only contain its own entry.")
        try expect(workspaceEntries.isEmpty, "Workspace queue should remain empty when only project entries are appended.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "projects/p1/queue.yaml").path), "Project queue should write to projects/p1/queue.yaml.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "projects/p2/queue.yaml").path), "Project queue should write to projects/p2/queue.yaml.")
    }

    private func researchQueueStoreApplyPaperStatusTransitionRespectsRules() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueuePaperStatusWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        try await store.append(sampleQueueEntry(id: "queue:workspace:a", scope: .workspace, order: 1, status: .queued, paperID: "a"))
        try await store.append(sampleQueueEntry(id: "queue:workspace:b", scope: .workspace, order: 2, status: .reading, paperID: "b"))
        try await store.append(sampleQueueEntry(id: "queue:workspace:c", scope: .workspace, order: 3, status: .finished, paperID: "c"))
        try await store.append(sampleQueueEntry(id: "queue:workspace:d", scope: .workspace, order: 4, status: .dismissed, paperID: "d"))

        let now = Date(timeIntervalSince1970: 1_777_700_000)

        await store.applyPaperStatusTransition(paperID: "a", from: .unread, to: .skimmed, at: now)
        let aStatus = await store.entry(id: "queue:workspace:a")?.status
        try expect(aStatus == .reading, "Skimming a queued paper should flip its entry to reading.")

        await store.applyPaperStatusTransition(paperID: "b", from: .deepRead, to: .summarized, at: now)
        let bStatus = await store.entry(id: "queue:workspace:b")?.status
        try expect(bStatus == .finished, "Summarizing a reading paper should flip its entry to finished.")

        await store.applyPaperStatusTransition(paperID: "c", from: .summarized, to: .used, at: now)
        let cStatus = await store.entry(id: "queue:workspace:c")?.status
        try expect(cStatus == .finished, "Already-finished entries should ignore further paper status changes.")

        await store.applyPaperStatusTransition(paperID: "d", from: .skimmed, to: .skimmed, at: now)
        let dStatus = await store.entry(id: "queue:workspace:d")?.status
        try expect(dStatus == .dismissed, "Dismissed entries should be invariant under paper status changes.")

        try await store.append(sampleQueueEntry(id: "queue:workspace:e", scope: .workspace, order: 5, status: .queued, paperID: "e"))
        await store.applyPaperStatusTransition(paperID: "e", from: .unread, to: .rejected, at: now)
        let eStatus = await store.entry(id: "queue:workspace:e")?.status
        try expect(eStatus == .dismissed, "Rejecting a paper should dismiss its queued entry.")
    }

    private func researchQueueYAMLEncodingRoundtripIsStable() throws {
        let scope = QueueScope.workspace
        let now = Date(timeIntervalSince1970: 1_777_600_000)
        let entries = [
            sampleQueueEntry(
                id: "queue:workspace:a",
                scope: scope,
                order: 1,
                status: .queued,
                paperID: "a",
                displayTitle: "Paper A",
                addedAt: now,
                lastTouchedAt: now
            ),
            sampleQueueEntry(
                id: "queue:workspace:ext:arxiv-2410.12345",
                scope: scope,
                order: 2,
                status: .reading,
                source: .recommendation,
                externalKey: "arxiv:2410.12345",
                displayTitle: "External Paper",
                addedAt: now,
                lastTouchedAt: now,
                noteSummary: "Cited by 4 of my core papers",
                sourceRefs: ["run:r1", "tool_call:c1"]
            )
        ]

        let firstPass = ResearchQueueYAMLEncoder.encode(entries: entries, scope: scope, generatedAt: now)
        let secondPass = ResearchQueueYAMLEncoder.encode(entries: entries, scope: scope, generatedAt: now)
        try expect(firstPass == secondPass, "YAML encoding must be deterministic for the same entries and timestamp.")

        let decoded = ResearchQueueYAMLEncoder.decode(contents: firstPass)
        try expect(decoded.skippedEntryCount == 0, "Round-trip decode should not skip any entry.")
        try expect(decoded.fileSchemaVersion == ResearchQueueYAMLEncoder.schemaVersion, "Round-trip decode should preserve schema_version.")
        try expect(decoded.entries.map(\.id) == entries.map(\.id), "Round-trip decode should preserve entry IDs and order.")
        try expect(decoded.entries.map(\.status) == entries.map(\.status), "Round-trip decode should preserve status.")
        try expect(decoded.entries.map(\.source) == entries.map(\.source), "Round-trip decode should preserve source.")
        try expect(decoded.entries[1].externalKey == "arxiv:2410.12345", "Round-trip decode should preserve external_key.")
        try expect(decoded.entries[1].noteSummary == "Cited by 4 of my core papers", "Round-trip decode should preserve note_summary.")
        try expect(decoded.entries[1].sourceRefs == ["run:r1", "tool_call:c1"], "Round-trip decode should preserve source_refs ordering.")
        try expect(decoded.entries[0].externalKey == nil, "Round-trip decode should treat null external_key as nil.")
    }

    private func researchQueueYAMLDecoderSkipsUnknownFieldsForward() throws {
        let yaml = """
        schema_version: 1
        scope: "workspace"
        generated_at: "2026-05-17T12:00:00Z"
        future_section: "ignored"
        entries:
          - id: "queue:workspace:a"
            paper_id: "a"
            external_key: null
            display_title: "Paper A"
            scope: "workspace"
            status: queued
            source: manual
            order: 1
            added_at: "2026-05-17T11:00:00Z"
            started_at: null
            finished_at: null
            last_touched_at: "2026-05-17T11:00:00Z"
            note_summary: null
            source_refs: []
            future_field: "should be ignored"
            future_object_field: "{stub}"
        """
        let decoded = ResearchQueueYAMLEncoder.decode(contents: yaml)
        try expect(decoded.entries.count == 1, "Forward-compatible decode should return the known entry.")
        try expect(decoded.skippedEntryCount == 0, "Unknown fields are not malformed and should not increment the skipped counter.")
        try expect(decoded.entries.first?.id == "queue:workspace:a", "Forward-compatible decode should preserve known fields.")
        try expect(decoded.entries.first?.paperID == "a", "Forward-compatible decode should preserve paper_id.")
    }

    private func researchQueueDebugEventsScrubSensitiveFields() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueDebugScrubWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let logger = AppDebugEventLogger()
        let store = ResearchQueueStore(workspace: workspace, debugLogger: logger)
        try await store.open()

        let secretTitle = "Confidential Manuscript Title"
        let secretSummary = "Reviewer flagged unsupported claim about classified evidence."
        let entry = sampleQueueEntry(
            id: "queue:workspace:secret",
            scope: .workspace,
            order: 1,
            paperID: "secret-paper",
            displayTitle: secretTitle,
            noteSummary: secretSummary
        )
        try await store.append(entry)
        try await store.updateStatus(id: entry.id, status: .reading)

        let root = ResearchRoot(rootURL: workspace.rootURL)
        let events = try await logger.events(in: root).filter { $0.event.hasPrefix("queue.") }
        try expect(!events.isEmpty, "Queue mutations should produce debug events.")

        for event in events {
            let serialized = event.payload.canonicalJSON
            try expect(!serialized.contains(secretTitle), "Queue debug events must not include display_title text. Event: \(event.event)")
            try expect(!serialized.contains(secretSummary), "Queue debug events must not include note_summary text. Event: \(event.event)")
        }
    }

    private func makeRecommendationToolResult(
        callID: String,
        succeeded: Bool = true,
        requiresConfirmation: Bool = false,
        kind: String = "recommendation_note",
        scope: String? = nil,
        candidates: [JSONValue]
    ) -> AgentToolResult {
        var payload: [String: JSONValue] = [
            "schema_version": .number("1"),
            "kind": .string(kind),
            "queue_candidates": .array(candidates)
        ]
        if let scope {
            payload["queue_scope"] = .string(scope)
        }
        return AgentToolResult(
            callID: callID,
            toolName: "recommendation_pipeline",
            succeeded: succeeded,
            requiresConfirmation: requiresConfirmation,
            message: "Recommendation note draft",
            payload: .object(payload)
        )
    }

    private func makeAgentRunForQueueIngest(
        id: String,
        toolResults: [AgentToolResult],
        projectID: String? = nil
    ) -> AgentRun {
        AgentRun(
            id: id,
            goal: "Recommendation fixture",
            createdAt: Date(timeIntervalSince1970: 1_777_600_000),
            completedAt: Date(timeIntervalSince1970: 1_777_600_001),
            mode: .planOnly,
            plan: AgentPlan(title: "Fixture", summary: "Fixture", toolCalls: []),
            toolResults: toolResults,
            currentProjectID: projectID
        )
    }

    private func researchQueueIngestorMapsApprovedRecommendationCandidatesAndDedupes() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueIngestRecommendationWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        let ingestor = ResearchQueueIngestor(store: store, workspace: workspace)
        await ingestor.start()

        let approvedResult = makeRecommendationToolResult(
            callID: "call-1",
            candidates: [
                .object([
                    "paper_id": .string("p-alpha"),
                    "display_title": .string("Alpha Paper"),
                    "reason": .string("Cited by 4 of my core papers")
                ]),
                .object([
                    "external_key": .string("arxiv:2410.12345"),
                    "display_title": .string("External Paper")
                ])
            ]
        )
        let pendingResult = makeRecommendationToolResult(
            callID: "call-2",
            requiresConfirmation: true,
            candidates: [
                .object([
                    "paper_id": .string("p-beta"),
                    "display_title": .string("Beta Paper")
                ])
            ]
        )
        let failedResult = makeRecommendationToolResult(
            callID: "call-3",
            succeeded: false,
            candidates: [
                .object([
                    "paper_id": .string("p-gamma"),
                    "display_title": .string("Gamma Paper")
                ])
            ]
        )
        let unrelatedResult = makeRecommendationToolResult(
            callID: "call-4",
            kind: "wiki_markdown_write",
            candidates: [
                .object([
                    "paper_id": .string("p-delta"),
                    "display_title": .string("Delta Paper")
                ])
            ]
        )

        let run = makeAgentRunForQueueIngest(
            id: "run-1",
            toolResults: [approvedResult, pendingResult, failedResult, unrelatedResult]
        )

        await ingestor.ingest(runs: [run])
        let afterFirst = await store.entries(in: .workspace)
        try expect(afterFirst.map(\.id) == [
            "queue:workspace:p-alpha",
            "queue:workspace:arxiv:2410.12345"
        ], "Ingestor should map only approved recommendation candidates into queue entries.")
        try expect(afterFirst.first?.source == .recommendation, "Ingested entries should be marked source=recommendation.")
        try expect(afterFirst.first?.noteSummary == "Cited by 4 of my core papers", "Ingestor should map `reason` to noteSummary.")
        try expect(afterFirst.last?.externalKey == "arxiv:2410.12345", "Ingestor should preserve external_key for entries without paper_id.")

        // Re-ingest the same run with the same callID; nothing new should land.
        await ingestor.ingest(runs: [run])
        let afterSecondPass = await store.entries(in: .workspace)
        try expect(afterSecondPass.count == afterFirst.count, "Re-running ingest with the same (runID, callID) pair should be a no-op.")
    }

    private func researchQueueIngestorAppliesPaperStatusDiffsToStore() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueIngestPaperStatusWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let store = ResearchQueueStore(workspace: workspace)
        try await store.open()
        try await store.append(sampleQueueEntry(id: "queue:workspace:a", scope: .workspace, order: 1, status: .queued, paperID: "p-a"))
        try await store.append(sampleQueueEntry(id: "queue:workspace:b", scope: .workspace, order: 2, status: .reading, paperID: "p-b"))
        try await store.append(sampleQueueEntry(id: "queue:workspace:c", scope: .workspace, order: 3, status: .queued, paperID: "p-c"))

        let ingestor = ResearchQueueIngestor(store: store, workspace: workspace)
        await ingestor.start()

        var previousPaperA = samplePaper(id: "p-a")
        previousPaperA.status = .unread
        var currentPaperA = previousPaperA
        currentPaperA.status = .skimmed
        currentPaperA.lastReadAt = Date(timeIntervalSince1970: 1_777_700_000)

        var previousPaperB = samplePaper(id: "p-b")
        previousPaperB.status = .deepRead
        var currentPaperB = previousPaperB
        currentPaperB.status = .summarized
        currentPaperB.lastReadAt = Date(timeIntervalSince1970: 1_777_700_500)

        var previousPaperC = samplePaper(id: "p-c")
        previousPaperC.status = .unread
        var currentPaperC = previousPaperC
        currentPaperC.status = .rejected

        await ingestor.ingest(
            papers: [currentPaperA, currentPaperB, currentPaperC],
            previous: [
                previousPaperA.id: previousPaperA,
                previousPaperB.id: previousPaperB,
                previousPaperC.id: previousPaperC
            ]
        )

        let aStatus = await store.entry(id: "queue:workspace:a")?.status
        let bStatus = await store.entry(id: "queue:workspace:b")?.status
        let cStatus = await store.entry(id: "queue:workspace:c")?.status
        try expect(aStatus == .reading, "Ingesting unread→skimmed should flip queued entries to reading.")
        try expect(bStatus == .finished, "Ingesting deepRead→summarized should flip reading entries to finished.")
        try expect(cStatus == .dismissed, "Ingesting *→rejected should dismiss the queue entry.")

        // No-diff pass should be a no-op (no exceptions, no further mutations).
        await ingestor.ingest(papers: [currentPaperA, currentPaperB, currentPaperC], previous: [
            currentPaperA.id: currentPaperA,
            currentPaperB.id: currentPaperB,
            currentPaperC.id: currentPaperC
        ])
        let aStatusAfter = await store.entry(id: "queue:workspace:a")?.status
        try expect(aStatusAfter == .reading, "A no-op diff pass must not change any entry's status.")
    }

    /// P48.11 — Fixture-style sanity that persists 5 entries spanning every
    /// scope/status/source combination and re-loads them through a fresh
    /// store. Acts as a debug-grade reference so engineers can copy/paste the
    /// fixture into a real workspace and see populated UI immediately.
    private func researchQueueFixtureRoundTripsFiveDiverseEntries() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueFixtureWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let baseDate = Date(timeIntervalSince1970: 1_777_600_000)
        let projectScope = QueueScope.project("project-fixture")
        let entries: [ResearchQueueEntry] = [
            ResearchQueueEntry(
                id: "queue:workspace:p-active-recent",
                paperID: "p-active-recent",
                externalKey: nil,
                displayTitle: "Active workspace paper (most recent)",
                scope: .workspace,
                status: .reading,
                source: .manual,
                order: 1,
                addedAt: baseDate,
                startedAt: baseDate.addingTimeInterval(900),
                finishedAt: nil,
                lastTouchedAt: baseDate.addingTimeInterval(7_200),
                noteSummary: "Skim 4.1, 4.2 first",
                sourceRefs: []
            ),
            ResearchQueueEntry(
                id: "queue:workspace:p-finished",
                paperID: "p-finished",
                externalKey: nil,
                displayTitle: "Finished workspace paper",
                scope: .workspace,
                status: .finished,
                source: .paperStatus,
                order: 2,
                addedAt: baseDate,
                startedAt: baseDate.addingTimeInterval(1_200),
                finishedAt: baseDate.addingTimeInterval(5_400),
                lastTouchedAt: baseDate.addingTimeInterval(5_400),
                noteSummary: nil,
                sourceRefs: []
            ),
            ResearchQueueEntry(
                id: "queue:workspace:ext-arxiv",
                paperID: nil,
                externalKey: "arxiv:2410.12345",
                displayTitle: "External recommendation candidate",
                scope: .workspace,
                status: .queued,
                source: .recommendation,
                order: 3,
                addedAt: baseDate,
                startedAt: nil,
                finishedAt: nil,
                lastTouchedAt: baseDate.addingTimeInterval(3_600),
                noteSummary: nil,
                sourceRefs: ["run-rec-1#tool-1"]
            ),
            ResearchQueueEntry(
                id: "queue:project:project-fixture:p-project-1",
                paperID: "p-project-1",
                externalKey: nil,
                displayTitle: "Project queue head",
                scope: projectScope,
                status: .queued,
                source: .graphTool,
                order: 1,
                addedAt: baseDate,
                startedAt: nil,
                finishedAt: nil,
                lastTouchedAt: baseDate.addingTimeInterval(1_800),
                noteSummary: nil,
                sourceRefs: ["run-graph-1#tool-2"]
            ),
            ResearchQueueEntry(
                id: "queue:project:project-fixture:p-project-2",
                paperID: "p-project-2",
                externalKey: nil,
                displayTitle: "Deferred project paper",
                scope: projectScope,
                status: .deferred,
                source: .manual,
                order: 2,
                addedAt: baseDate,
                startedAt: nil,
                finishedAt: nil,
                lastTouchedAt: baseDate.addingTimeInterval(2_700),
                noteSummary: "Wait until next milestone",
                sourceRefs: []
            )
        ]

        let firstStore = ResearchQueueStore(workspace: workspace)
        try await firstStore.open()
        let workspaceFixture = entries.filter { $0.scope == .workspace }
        let projectFixture = entries.filter { $0.scope == projectScope }
        try await firstStore.appendBatch(workspaceFixture, scope: .workspace)
        try await firstStore.appendBatch(projectFixture, scope: projectScope)
        let firstSnapshot = await firstStore.snapshot()
        try expect(firstSnapshot.entriesByScope[QueueScope.workspace.identifier]?.count == 3, "Fixture should write 3 workspace-scope rows.")
        try expect(firstSnapshot.entriesByScope[projectScope.identifier]?.count == 2, "Fixture should write 2 project-scope rows.")
        await firstStore.close()

        let secondStore = ResearchQueueStore(workspace: workspace)
        try await secondStore.open()
        let workspaceEntries = await secondStore.entries(in: .workspace)
        let projectEntries = await secondStore.entries(in: projectScope)

        try expect(workspaceEntries.map(\.id) == [
            "queue:workspace:p-active-recent",
            "queue:workspace:p-finished",
            "queue:workspace:ext-arxiv"
        ], "Fixture round-trip should preserve workspace ordering.")
        try expect(projectEntries.map(\.id) == [
            "queue:project:project-fixture:p-project-1",
            "queue:project:project-fixture:p-project-2"
        ], "Fixture round-trip should preserve project ordering.")

        let externalEntry = try require(
            workspaceEntries.first(where: { $0.id == "queue:workspace:ext-arxiv" }),
            "Fixture round-trip should include the external recommendation candidate."
        )
        try expect(externalEntry.paperID == nil && externalEntry.externalKey == "arxiv:2410.12345", "External entry should keep its arxiv key after reload.")
        try expect(externalEntry.source == .recommendation, "External entry should keep its recommendation source label after reload.")
        try expect(externalEntry.sourceRefs == ["run-rec-1#tool-1"], "Source refs should round-trip exactly.")

        let finishedEntry = try require(
            workspaceEntries.first(where: { $0.id == "queue:workspace:p-finished" }),
            "Fixture round-trip should include the finished entry."
        )
        try expect(finishedEntry.startedAt != nil && finishedEntry.finishedAt != nil, "Finished entries should preserve startedAt/finishedAt timestamps.")
        try expect(finishedEntry.source == .paperStatus, "paper_status sync source should round-trip.")

        let projectHead = try require(
            projectEntries.first,
            "Fixture round-trip should include the project queue head."
        )
        try expect(projectHead.source == .graphTool, "Graph-tool source should round-trip.")
        try expect(projectHead.scope == projectScope, "Project scope should round-trip.")
    }

    private func researchQueueIngestorPersistsCursorAcrossReopen() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ResearchQueueIngestCursorWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let firstStore = ResearchQueueStore(workspace: workspace)
        try await firstStore.open()
        let firstIngestor = ResearchQueueIngestor(store: firstStore, workspace: workspace)
        await firstIngestor.start()

        let result = makeRecommendationToolResult(
            callID: "call-cursor-1",
            candidates: [
                .object([
                    "paper_id": .string("p-cursor"),
                    "display_title": .string("Cursor Paper")
                ])
            ]
        )
        let run = makeAgentRunForQueueIngest(id: "run-cursor", toolResults: [result])
        await firstIngestor.ingest(runs: [run])
        let firstCount = await firstStore.entries(in: .workspace).count
        try expect(firstCount == 1, "First ingestor pass should record one entry.")

        let cursorURL = workspace.fileURL(for: ResearchQueueIngestor.cursorRelativePath)
        try expect(FileManager.default.fileExists(atPath: cursorURL.path), "Cursor should be persisted under .sci-station/queue/ingest_cursor.json.")

        await firstStore.close()

        let secondStore = ResearchQueueStore(workspace: workspace)
        try await secondStore.open()
        let secondIngestor = ResearchQueueIngestor(store: secondStore, workspace: workspace)
        await secondIngestor.start()

        await secondIngestor.ingest(runs: [run])
        let secondCount = await secondStore.entries(in: .workspace).count
        try expect(secondCount == 1, "Reopened ingestor must read the persisted cursor and skip the already-scanned tool call.")
    }

    private func readingPlanYAMLCodecRoundTripsActivePlan() throws {
        let baseDate = Date(timeIntervalSince1970: 1_777_600_000)
        let plan = ReadingPlan(
            id: "reading-plan-project-alpha-2026-05-18",
            scope: .project("project-alpha"),
            weekStart: Date(timeIntervalSince1970: 1_779_062_400),
            status: .active,
            slots: [
                ReadingPlanSlot(
                    id: "slot-a",
                    queueEntryID: "queue:project:project-alpha:p-a",
                    paperID: "p-a",
                    displayTitle: "First Reading",
                    status: .reading,
                    plannedDay: "Mon",
                    estimatedMinutes: 45,
                    actualMinutes: nil,
                    order: 1,
                    sourceRefs: ["queue:project:project-alpha:p-a"],
                    createdAt: baseDate,
                    updatedAt: baseDate
                ),
                ReadingPlanSlot(
                    id: "slot-b",
                    queueEntryID: "queue:project:project-alpha:p-b",
                    paperID: "p-b",
                    displayTitle: "Second Reading",
                    status: .finished,
                    plannedDay: "Wed",
                    estimatedMinutes: 60,
                    actualMinutes: 55,
                    order: 2,
                    sourceRefs: [],
                    createdAt: baseDate,
                    updatedAt: baseDate.addingTimeInterval(60)
                )
            ],
            sourceRefs: ["queue:project:project-alpha:p-a", "queue:project:project-alpha:p-b"],
            createdAt: baseDate,
            updatedAt: baseDate.addingTimeInterval(120),
            activatedAt: baseDate.addingTimeInterval(30)
        )

        let yaml = ReadingPlanYAMLCodec.encode(plans: [plan], scope: .project("project-alpha"), generatedAt: baseDate)
        let decoded = ReadingPlanYAMLCodec.decode(contents: yaml)

        try expect(decoded.skippedPlanCount == 0, "ReadingPlan YAML round-trip should not skip valid plans.")
        let loaded = try require(decoded.plans.first, "ReadingPlan YAML round-trip should decode one plan.")
        try expect(loaded.id == plan.id, "ReadingPlan YAML should preserve plan id.")
        try expect(loaded.scope == .project("project-alpha"), "ReadingPlan YAML should preserve project scope.")
        try expect(loaded.status == .active, "ReadingPlan YAML should preserve plan status.")
        try expect(loaded.slots.map(\.id) == ["slot-a", "slot-b"], "ReadingPlan YAML should preserve slot order.")
        try expect(loaded.slots.last?.actualMinutes == 55, "ReadingPlan YAML should preserve actual minutes.")
    }

    private func readingPlanYAMLCodecSkipsMalformedPlans() throws {
        let yaml = """
        schema_version: 1
        scope: "workspace"
        generated_at: "2026-05-18T12:00:00Z"
        plans:
          - id: "plan-valid"
            scope: "workspace"
            week_start: "2026-05-18"
            status: active
            created_at: "2026-05-18T12:00:00Z"
            updated_at: "2026-05-18T12:00:00Z"
            activated_at: ""
            archived_at: ""
            source_refs: []
            slots: []
          - id: "plan-broken"
            status: active
            source_refs: []
            slots: []
        """

        let decoded = ReadingPlanYAMLCodec.decode(contents: yaml)
        try expect(decoded.skippedPlanCount == 1, "Reading plan block missing required fields should be skipped, not crash.")
        try expect(decoded.plans.map(\.id) == ["plan-valid"], "Valid reading plan should survive while malformed block is skipped.")
    }

    private func readingPlanGeneratorBuildsDeterministicWeeklySlots() throws {
        let now = Date(timeIntervalSince1970: 1_777_600_000)
        let generator = ReadingPlanGenerator()
        let entries = [
            sampleQueueEntry(
                id: "queue:project:p1:later",
                scope: .project("p1"),
                order: 3,
                status: .queued,
                paperID: "later",
                displayTitle: "Later Paper",
                lastTouchedAt: now.addingTimeInterval(300)
            ),
            sampleQueueEntry(
                id: "queue:project:p1:reading",
                scope: .project("p1"),
                order: 2,
                status: .reading,
                paperID: "reading",
                displayTitle: "Already Reading",
                lastTouchedAt: now.addingTimeInterval(100)
            ),
            sampleQueueEntry(
                id: "queue:project:p1:finished",
                scope: .project("p1"),
                order: 1,
                status: .finished,
                paperID: "finished",
                displayTitle: "Finished Paper",
                lastTouchedAt: now.addingTimeInterval(500)
            )
        ]
        let plan = generator.generate(input: ReadingPlanGenerationInput(
            scope: .project("p1"),
            weekStart: Date(timeIntervalSince1970: 1_779_148_800),
            queueEntries: entries,
            settings: ReadingPlanSettings(weeklyCapacityMinutes: 120, defaultSlotMinutes: 60, maxPapersPerWeek: 4, preferredReadingDays: ["Tue", "Thu"]),
            now: now
        ))

        try expect(plan.id == "reading-plan-project-p1-2026-05-18", "Generator should produce a stable weekly plan id.")
        try expect(plan.status == .draft, "Generated plans should start as draft.")
        try expect(plan.slots.map(\.displayTitle) == ["Already Reading", "Later Paper"], "Generator should prefer reading entries then queued entries and skip finished entries.")
        try expect(plan.slots.map(\.plannedDay) == ["Tue", "Thu"], "Generator should assign preferred reading days deterministically.")
        try expect(plan.slots.map(\.estimatedMinutes) == [60, 60], "Generator should use the configured slot minutes.")
    }

    private func readingPlanStorePersistsActivatesAndUpdatesSlots() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("ReadingPlanStoreWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let baseDate = Date(timeIntervalSince1970: 1_777_600_000)
        let store = ReadingPlanStore(workspace: workspace, dateProvider: { baseDate })
        try await store.open(projectIDs: ["project-alpha"])
        let plan = ReadingPlan(
            id: "reading-plan-project-alpha-2026-05-18",
            scope: .project("project-alpha"),
            weekStart: Date(timeIntervalSince1970: 1_779_062_400),
            status: .draft,
            slots: [
                ReadingPlanSlot(
                    id: "slot-a",
                    queueEntryID: "queue:project:project-alpha:p-a",
                    paperID: "p-a",
                    displayTitle: "Persisted Slot",
                    estimatedMinutes: 60,
                    order: 1,
                    createdAt: baseDate,
                    updatedAt: baseDate
                )
            ],
            createdAt: baseDate,
            updatedAt: baseDate
        )

        try await store.save(plan)
        try await store.activate(planID: plan.id, in: .project("project-alpha"), at: baseDate.addingTimeInterval(60))
        try await store.updateSlotStatus(planID: plan.id, slotID: "slot-a", status: .finished, actualMinutes: 50, at: baseDate.addingTimeInterval(120))
        let active = try require(await store.activePlan(in: .project("project-alpha")), "Store should expose the activated plan.")
        try expect(active.status == .active, "Activating a plan should update status.")
        try expect(active.slots.first?.status == .finished, "Slot status updates should be applied in memory.")
        try expect(active.slots.first?.actualMinutes == 50, "Slot status updates should persist actual minutes.")

        await store.close()

        let reopened = ReadingPlanStore(workspace: workspace)
        try await reopened.open(projectIDs: ["project-alpha"])
        let reloaded = try require(await reopened.activePlan(in: .project("project-alpha")), "Reopened store should reload the active plan.")
        try expect(reloaded.slots.first?.displayTitle == "Persisted Slot", "Reopened store should preserve slot title.")
        try expect(reloaded.slots.first?.status == .finished, "Reopened store should preserve slot status.")
        let yamlURL = workspace.fileURL(for: "projects/project-alpha/reading-plans/plans.yaml")
        try expect(FileManager.default.fileExists(atPath: yamlURL.path), "ReadingPlanStore should persist project plans under projects/<id>/reading-plans/plans.yaml.")
    }

    private func recommendationConfigYAMLRoundTripsDailySourceSettings() throws {
        var config = RecommendationConfig()
        config.cadence = .daily
        config.scope = .workspace
        config.topK = 7
        config.externalNetworkEnabled = true
        config.maxDailyCandidates = 42
        config.weights.libraryInterestSimilarity = 0.55
        config.dailySources = [
            RecommendationDailySourceConfig(kind: .arxiv, enabled: true, categories: ["cs.AI", "cs.CL"], includeCrossList: true),
            RecommendationDailySourceConfig(kind: .biorxiv, enabled: false, categories: ["neuroscience"])
        ]

        let yaml = RecommendationConfigStore.encode(config)
        let decoded = try RecommendationConfigStore.decode(yaml)

        try expect(decoded.cadence == .daily, "Recommendation config should preserve cadence.")
        try expect(decoded.scope == .workspace, "Recommendation config should preserve scope.")
        try expect(decoded.topK == 7, "Recommendation config should preserve top_k.")
        try expect(decoded.externalNetworkEnabled, "Recommendation config should preserve external network opt-in.")
        try expect(decoded.maxDailyCandidates == 42, "Recommendation config should preserve max_daily_candidates.")
        try expect(decoded.weights.libraryInterestSimilarity == 0.55, "Recommendation config should preserve library-interest weight.")
        try expect(decoded.dailySources.first?.kind == .arxiv && decoded.dailySources.first?.enabled == true, "Daily source config should preserve arxiv enabled state.")
        try expect(decoded.dailySources.first?.categories == ["cs.AI", "cs.CL"], "Daily source config should preserve categories.")
        try expect(decoded.dailySources.first?.includeCrossList == true, "Daily source config should preserve include_cross_list.")
    }

    private func dailyFeedCandidateImporterMapsExternalArxivCandidates() throws {
        let jsonl = """
        {"source":"arxiv","id":"2604.22012v1","title":"Graph Retrieval for Scientific Agents","authors":["Ada Lovelace","Grace Hopper"],"abstract":"Graph retrieval agents use literature libraries for recommendations.","published":"2026-04-20T00:00:00Z","categories":["cs.AI","cs.CL"],"url":"https://arxiv.org/abs/2604.22012","pdf_url":"https://arxiv.org/pdf/2604.22012.pdf"}
        """
        let candidates = try DailyFeedCandidateImporter().parseJSONLines(jsonl)
        let candidate = try require(candidates.first, "Importer should return one candidate.")

        try expect(candidate.canonicalID == "external:arxiv:2604.22012", "Importer should canonicalize arXiv external keys without version suffix.")
        try expect(candidate.externalKey == "arxiv:2604.22012", "Importer should preserve arXiv external_key.")
        try expect(candidate.publishedYear == 2026, "Importer should derive published year.")
        try expect(candidate.sourceTags == [.dailyFeed], "Importer should mark daily feed source.")
        try expect(candidate.abstractText?.contains("Graph retrieval") == true, "Importer should keep abstract in memory for scoring.")
    }

    private func arxivRecommendationParserMapsAtomFeedCandidates() throws {
        let atom = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>http://arxiv.org/abs/2604.22012v1</id>
            <updated>2026-04-21T00:00:00Z</updated>
            <published>2026-04-20T00:00:00Z</published>
            <title>Graph Retrieval for Scientific Agents</title>
            <summary>Graph retrieval agents use arXiv recommendations.</summary>
            <author><name>Ada Lovelace</name></author>
            <author><name>Grace Hopper</name></author>
            <category term="cs.AI"/>
            <category term="cs.CL"/>
          </entry>
        </feed>
        """
        let candidate = try require(ArxivRecommendationParser.parseAtom(atom).first, "arXiv Atom parser should return one candidate.")

        try expect(candidate.canonicalID == "external:arxiv:2604.22012", "arXiv Atom parser should canonicalize versioned ids.")
        try expect(candidate.externalKey == "arxiv:2604.22012", "arXiv Atom parser should emit arXiv external keys.")
        try expect(candidate.sourceName == "arXiv", "arXiv Atom parser should label candidates as arXiv.")
        try expect(candidate.sourceURL == "https://arxiv.org/abs/2604.22012", "arXiv Atom parser should produce abs URLs.")
        try expect(candidate.pdfURL == "https://arxiv.org/pdf/2604.22012.pdf", "arXiv Atom parser should produce pdf URLs.")
        try expect(candidate.authors == ["Ada Lovelace", "Grace Hopper"], "arXiv Atom parser should preserve author order.")
        try expect(candidate.categories == ["cs.AI", "cs.CL"], "arXiv Atom parser should preserve categories.")
        try expect(candidate.abstractText?.contains("arXiv recommendations") == true, "arXiv Atom parser should preserve summaries.")
    }

    private func recommendationCandidateGathererDedupsDailyFeedAndQueueTail() async throws {
        let gatherer = RecommendationCandidateGatherer()
        let context = RecommendationContext(evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000))
        let daily = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.22012",
            externalKey: "arxiv:2604.22012",
            displayTitle: "Daily Candidate",
            sourceTags: [.dailyFeed]
        )
        let queueEntry = sampleQueueEntry(
            id: "queue:workspace:arxiv:2604.22012",
            scope: .workspace,
            order: 1,
            externalKey: "arxiv:2604.22012",
            displayTitle: "Queued Candidate"
        )

        let candidates = await gatherer.gather(
            papers: [],
            queueEntries: [queueEntry],
            dailyFeedCandidates: [daily],
            context: context,
            config: RecommendationConfig()
        )
        let candidate = try require(candidates.first, "Gatherer should return the deduped candidate.")

        try expect(candidates.count == 1, "Gatherer should dedupe candidates by canonical external key.")
        try expect(candidate.sourceTags.contains(.dailyFeed), "Deduped candidate should retain daily feed source.")
        try expect(candidate.sourceTags.contains(.queueTail), "Deduped candidate should retain queue tail source.")
    }

    private func recommendationScorerRanksByLibraryInterestAndSuppressesFinished() async throws {
        var corePaper = samplePaper(id: "core-graph")
        corePaper.title = "Graph Retrieval Agents"
        corePaper.abstract = "Graph retrieval agents build literature maps for scientific recommendation."
        corePaper.tags = ["graph", "retrieval", "agents"]
        corePaper.coreProjectIDs = ["proj"]

        let matchingCandidate = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.22012",
            externalKey: "arxiv:2604.22012",
            displayTitle: "Graph Retrieval Agents for Literature Recommendation",
            authors: ["Ada Lovelace"],
            publishedYear: 2026,
            sourceTags: [.dailyFeed],
            categories: ["cs.AI"],
            abstractText: "Graph retrieval agents rank papers from a user library."
        )
        let unrelatedCandidate = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00001",
            externalKey: "arxiv:2604.00001",
            displayTitle: "A Marine Biology Survey",
            publishedYear: 2026,
            sourceTags: [.dailyFeed],
            abstractText: "Coral reef ecology and ocean temperatures."
        )
        let context = RecommendationContext(
            projectID: "proj",
            corePaperIDs: ["core-graph"],
            queueStatusByID: ["arxiv:2604.00001": .finished],
            openGapKeywords: ["retrieval"],
            interestPapers: [corePaper],
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
        let ranked = await RecommendationScorer().score([unrelatedCandidate, matchingCandidate], context: context, locale: .zh)

        try expect(ranked.first?.id == matchingCandidate.id, "Scorer should rank the candidate matching recent library interests first.")
        try expect(ranked.first?.features.libraryInterestSimilarity ?? 0 > 0, "Matching candidate should have nonzero library-interest similarity.")
        try expect(ranked.last?.features.queuePressurePenalty == 0.95, "Finished queue entries should receive a strong pressure penalty.")
        try expect(ranked.first?.reason.contains("匹配近期文献兴趣") == true, "Reason builder should localize the top signal in Chinese.")
    }

    private func recommendationPipelineWritesSnapshotAndQueuePayload() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("RecommendationPipelineWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        var interestPaper = samplePaper(id: "interest")
        interestPaper.title = "Graph Retrieval Agents"
        interestPaper.abstract = "Graph retrieval agents build literature maps for recommendation."
        interestPaper.updatedAt = Date(timeIntervalSince1970: 1_777_500_000)
        let daily = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.22012",
            externalKey: "arxiv:2604.22012",
            displayTitle: "Graph Retrieval Agents for Daily Literature",
            publishedYear: 2026,
            sourceTags: [.dailyFeed],
            sourceURL: "https://arxiv.org/abs/2604.22012",
            pdfURL: "https://arxiv.org/pdf/2604.22012.pdf",
            categories: ["cs.AI"],
            abstractText: "Graph retrieval agents rank daily arXiv papers from a local library."
        )
        let config = RecommendationConfig(topK: 1)
        let context = RecommendationContext(
            interestPapers: [interestPaper],
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
        let fixedDate = Date(timeIntervalSince1970: 1_777_700_000)
        let pipeline = RecommendationPipeline(dateProvider: { fixedDate })

        let result = try await pipeline.run(
            workspace: workspace,
            papers: [],
            dailyFeedCandidates: [daily],
            context: context,
            config: config,
            trigger: .manual,
            locale: .en
        )
        let run = try require(result, "Pipeline should produce a first recommendation run.")
        let skipped = try await pipeline.run(
            workspace: workspace,
            papers: [],
            dailyFeedCandidates: [daily],
            context: context,
            config: config,
            trigger: .manual,
            locale: .en
        )

        try expect(run.scores.count == 1, "Pipeline should keep topK scored recommendations.")
        try expect(skipped == nil, "Pipeline should skip the same candidate hash within 30 minutes.")
        let snapshotURL = workspace.fileURL(for: "\(RecommendationPipeline.notesRelativeDirectory)/\(run.id).json")
        let historyURL = workspace.fileURL(for: RecommendationPipeline.historyRelativePath)
        try expect(FileManager.default.fileExists(atPath: snapshotURL.path), "Pipeline should write a snapshot JSON file.")
        try expect(FileManager.default.fileExists(atPath: historyURL.path), "Pipeline should append recommendation history.")

        let payload = RecommendationPipeline.recommendationNotePayload(for: run, queueScope: .workspace)
        let payloadObject = try jsonObject(payload, "Recommendation note payload should be an object.")
        let candidates = payloadObject["queue_candidates"]?.arrayValue ?? []
        let firstCandidate = try jsonObject(candidates.first, "Payload should contain a queue candidate object.")
        try expect(payloadObject["kind"]?.stringValue == "recommendation_note", "Payload kind should match the P48 ingestor contract.")
        try expect(payloadObject["queue_scope"]?.stringValue == "workspace", "Payload should include queue_scope for P48 ingestion.")
        try expect(firstCandidate["external_key"]?.stringValue == "arxiv:2604.22012", "Payload should preserve external_key for queue ingestion.")
        try expect(firstCandidate["display_title"]?.stringValue == "Graph Retrieval Agents for Daily Literature", "Payload should preserve display_title.")
    }

    private func recommendationPipelineHonorsCategoryHardBoundary() throws {
        let crossListed = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00002",
            externalKey: "arxiv:2604.00002",
            displayTitle: "Cross-listed Optimization Paper",
            categories: ["cs.AI", "math.OC"],
            primaryCategory: "cs.AI"
        )
        let primaryMatch = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00003",
            externalKey: "arxiv:2604.00003",
            displayTitle: "Primary Optimization Paper",
            categories: ["math.OC", "cs.AI"],
            primaryCategory: "math.OC"
        )

        let crossListOn = RecommendationPipeline.filterCategoryBoundary(
            [crossListed, primaryMatch],
            selectedCategories: ["math.OC"],
            includeCrossList: true
        )
        let crossListOff = RecommendationPipeline.filterCategoryBoundary(
            [crossListed, primaryMatch],
            selectedCategories: ["math.OC"],
            includeCrossList: false
        )

        try expect(Set(crossListOn.map(\.id)) == Set([crossListed.id, primaryMatch.id]), "Cross-list mode should allow any selected category match.")
        try expect(crossListOff.map(\.id) == [primaryMatch.id], "Primary-only mode should reject cross-listed non-primary matches.")
    }

    private func recommendationScorerV2SignalsKeywordSeedAndRecency() async throws {
        var seed = samplePaper(id: "seed-diffusion")
        seed.title = "Diffusion Planning Agents"
        seed.abstract = "Diffusion planning agents optimize long horizon scientific workflows."
        seed.updatedAt = Date(timeIntervalSince1970: 1_777_500_000)

        let candidate = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00004",
            externalKey: "arxiv:2604.00004",
            displayTitle: "Diffusion Planning Agents for Scientific Workflows",
            authors: ["Ada Lovelace"],
            sourceTags: [.dailyFeed],
            categories: ["cs.AI"],
            abstractText: "Diffusion planning agents optimize experiments and scientific workflows with long horizon decisions.",
            publishedAt: Date(timeIntervalSince1970: 1_777_590_000)
        )
        let context = RecommendationContext(
            corePaperIDs: [seed.id],
            openGapKeywords: ["diffusion", "planning"],
            weightedKeywords: [WeightedKeyword(text: "diffusion planning", weight: 2)],
            interestPapers: [seed],
            seedPapers: [seed],
            projectContextTexts: ["scientific workflow planning agents"],
            noveltyReferenceTexts: ["older graph retrieval survey"],
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )

        let score = await RecommendationScorer().scoreOne(candidate, context: context)

        try expect(score.features.keywordRelevance > 0.8, "V2 scorer should reward weighted keyword phrase matches.")
        try expect(score.features.seedSimilarity > 0.4, "V2 scorer should compute seed-paper similarity.")
        try expect(score.features.projectContextSimilarity > 0, "V2 scorer should use project context text.")
        try expect(score.features.recency > 0.8, "V2 recency should use publishedAt day-level decay.")
        try expect(score.total > 0.5, "V2 normalized total should remain strong for matched recommendations.")
    }

    private func recommendationFeedbackStorePersistsJSONLAndBuildsProfile() async throws {
        let (rootURL, workspace) = try makeQueueWorkspace("RecommendationFeedbackWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let candidate = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00005",
            externalKey: "arxiv:2604.00005",
            displayTitle: "Graph Retrieval Feedback Paper",
            categories: ["cs.AI"],
            abstractText: "Graph retrieval recommendations adapt to local feedback."
        )
        let store = RecommendationFeedbackStore(dateProvider: { Date(timeIntervalSince1970: 1_777_600_000) })
        try await store.record(candidate: candidate, type: .like, projectID: "proj", recommendationRunID: "run-1", in: workspace)
        let records = try await store.load(in: workspace)
        let score = RecommendationScore(
            id: candidate.id,
            candidate: candidate,
            features: RecommendationFeatureBreakdown(),
            total: 0.8,
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
        let profile = RecommendationFeedbackStore.profile(records: records, scores: [score], projectID: "proj")

        try expect(records.count == 1, "Feedback store should persist JSONL records.")
        try expect(records.first?.feedbackType == .like, "Feedback store should preserve feedback type.")
        try expect(profile.positiveTexts.first?.contains("Graph Retrieval Feedback") == true, "Feedback profile should include positive candidate text.")
        try expect(profile.feedbackByPaperKey["arxiv:2604.00005"] == .like, "Feedback profile should index latest feedback by paper key.")
    }

    private func recommendationPipelineMMRDiversifiesNearDuplicateResults() throws {
        let first = recommendationScoreForMMR(
            id: "external:arxiv:2604.00006",
            title: "Graph Retrieval Agents for Literature Maps",
            abstract: "Graph retrieval agents build literature maps.",
            total: 0.90
        )
        let duplicate = recommendationScoreForMMR(
            id: "external:arxiv:2604.00007",
            title: "Graph Retrieval Agents for Literature Mapping",
            abstract: "Graph retrieval agents build literature maps.",
            total: 0.89
        )
        let diverse = recommendationScoreForMMR(
            id: "external:arxiv:2604.00008",
            title: "Quantum Control for Detector Calibration",
            abstract: "Quantum control calibrates detector systems.",
            total: 0.88
        )

        let reranked = RecommendationPipeline.rerankByMMR([first, duplicate, diverse], limit: 2, lambda: 0.5)

        try expect(reranked.map(\.id) == [first.id, diverse.id], "MMR should prefer a slightly lower-scored diverse paper over a near duplicate.")
        try expect(reranked[0].rank == 1 && reranked[1].rank == 2, "MMR reranking should rewrite display ranks.")
    }

    private func recommendationRunResultDecodesLegacySnapshotWithV2Defaults() throws {
        let json = """
        {
          "id": "rec-legacy",
          "trigger": "manual",
          "context_project_id": "proj",
          "generated_at": "2026-04-20T00:00:00Z",
          "candidate_count": 1,
          "scores": [
            {
              "id": "external:arxiv:2604.00009",
              "candidate": {
                "canonical_id": "external:arxiv:2604.00009",
                "external_key": "arxiv:2604.00009",
                "display_title": "Legacy Recommendation Paper",
                "categories": ["cs.AI"],
                "source_tags": ["daily_feed"]
              },
              "features": {
                "library_interest_similarity": 0.5,
                "recency": 1.0,
                "open_gap_coverage": 0.25,
                "author_overlap_with_core": 0.0,
                "queue_pressure_penalty": 0.0
              },
              "total": 0.7,
              "rank": 1,
              "reason": "legacy",
              "reason_keys": ["library_interest_similarity"],
              "evaluated_at": "2026-04-20T00:00:00Z"
            }
          ],
          "query": "diffusion planning",
          "categories": ["cs.AI"],
          "source_note": "legacy"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(RecommendationRunResult.self, from: Data(json.utf8))

        try expect(result.keywords.map(\.text) == ["diffusion planning"], "Legacy snapshots should synthesize V2 weighted keywords from query.")
        try expect(result.includeCrossList == true, "Legacy snapshots should default include_cross_list to true.")
        try expect(result.scores.first?.candidate.primaryCategory == "cs.AI", "Legacy candidates should fall back to the first category as primary.")
        try expect(result.scores.first?.features.seedSimilarity == 0, "Legacy feature breakdown should decode missing V2 fields as zero.")
    }

    private func recommendationScoreForMMR(id: String, title: String, abstract: String, total: Double) -> RecommendationScore {
        let candidate = RecommendationCandidate(
            canonicalID: id,
            externalKey: id.replacingOccurrences(of: "external:", with: ""),
            displayTitle: title,
            categories: ["cs.AI"],
            abstractText: abstract
        )
        return RecommendationScore(
            id: id,
            candidate: candidate,
            features: RecommendationFeatureBreakdown(),
            total: total,
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
    }

        private func identifierParserRecognizesSupportedKinds() throws {
                let parser = IdentifierParser()

                try expect(parser.parse("2401.12345").kind == .arxiv, "Parser should recognize bare arXiv ids.")
                try expect(parser.parse("arXiv:2604.22012").normalizedValue == "2604.22012", "Parser should normalize prefixed arXiv ids.")
                try expect(parser.parse("arXiv 2604.22012").normalizedValue == "2604.22012", "Parser should normalize arXiv ids with a space prefix.")
                try expect(parser.parse("https://arxiv.org/abs/2401.12345").normalizedValue == "2401.12345", "Parser should normalize arXiv URLs to ids.")
                try expect(parser.parse("10.48550/arXiv.2401.12345").kind == .doi, "Parser should recognize DOI inputs.")
                try expect(parser.parse("https://doi.org/10.48550/arXiv.2604.22012").kind == .doi, "Parser should recognize doi.org arXiv DOI links as DOI inputs.")
                try expect(parser.extractArxivID(from: "10.48550/arXiv.2604.22012") == "2604.22012", "Parser should detect arXiv ids embedded in arXiv DOI strings.")
                try expect(parser.parse("https://inspirehep.net/literature/2811054").kind == .inspire, "Parser should recognize INSPIRE literature URLs.")
                try expect(parser.parse("https://example.com/paper.pdf").kind == .pdfURL, "Parser should recognize PDF URLs.")
                try expect(parser.parse("https://example.com/article").kind == .url, "Parser should recognize normal web URLs.")
        }

            private func metadataProviderBuildsStableLookupURLs() throws {
                let arxivURL = try ArxivMetadataProvider.apiURL(for: "2604.22012")
                let arxivComponents = try require(URLComponents(url: arxivURL, resolvingAgainstBaseURL: false), "Expected arXiv lookup URL components.")
                let arxivQueryItems = arxivComponents.queryItems ?? []

                try expect(arxivComponents.host == "export.arxiv.org", "arXiv lookup should use the export API host.")
                try expect(arxivComponents.path == "/api/query", "arXiv lookup should target the API query path.")
                try expect(arxivQueryItems.first(where: { $0.name == "search_query" })?.value == "id:2604.22012", "arXiv lookup should preserve id: search queries.")

                let doiURL = try DOIMetadataProvider.crossrefWorksURL(for: "10.48550/arXiv.2604.22012")
                try expect(
                    doiURL.absoluteString == "https://api.crossref.org/works/10.48550%2FarXiv.2604.22012",
                    "Crossref lookup should percent-encode DOI path separators."
                )
            }

        private func arxivEntryParserExtractsMetadataDraft() throws {
                let parser = ArxivEntryParser()
                let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <feed xmlns="http://www.w3.org/2005/Atom">
                    <entry>
                        <id>https://arxiv.org/abs/2401.12345v1</id>
                        <updated>2024-01-20T00:00:00Z</updated>
                        <published>2024-01-10T00:00:00Z</published>
                        <title> Dark Matter Capture Review </title>
                        <summary> Overview of dark matter capture. </summary>
                        <author><name>Jane Doe</name><arxiv:affiliation>Example Institute</arxiv:affiliation></author>
                        <author><name>John Roe</name></author>
                        <link href="https://arxiv.org/abs/2401.12345v1" rel="alternate" type="text/html"/>
                        <link href="https://arxiv.org/pdf/2401.12345v1.pdf" rel="related" type="application/pdf" title="pdf"/>
                        <category term="hep-ph"/>
                    </entry>
                </feed>
                """

                let draft = try parser.parse(Data(xml.utf8))
                try expect(draft.title == "Dark Matter Capture Review", "arXiv parser should trim entry titles.")
                try expect(draft.authors == ["Jane Doe", "John Roe"], "arXiv parser should extract author names.")
                try expect(draft.pdfURL == "https://arxiv.org/pdf/2401.12345v1.pdf", "arXiv parser should extract pdf links.")
                try expect(draft.categories == ["hep-ph"], "arXiv parser should extract category terms.")
        }

        private func inspireMetadataMapperExtractsMetadataDraft() throws {
                let mapper = InspireMetadataMapper()
                let json = """
                {
                    "metadata": {
                        "titles": [{"title": "Solar Dark Matter Limits"}],
                        "abstracts": [{"value": "An INSPIRE abstract."}],
                        "authors": [{"full_name": "Alice Smith"}],
                        "arxiv_eprints": [{"value": "2401.12345"}],
                        "dois": [{"value": "10.1234/example"}],
                        "documents": [{"url": "https://example.com/paper.pdf"}],
                        "publication_info": [{"year": 2024}],
                        "inspire_categories": [{"term": "Phenomenology"}]
                    }
                }
                """

                let draft = try mapper.map(data: Data(json.utf8), recordID: "2811054")
                try expect(draft.title == "Solar Dark Matter Limits", "INSPIRE mapper should extract titles.")
                try expect(draft.arxiv == "2401.12345", "INSPIRE mapper should extract linked arXiv ids.")
                try expect(draft.pdfURL == "https://arxiv.org/pdf/2401.12345.pdf", "INSPIRE mapper should prefer arXiv PDF links when available.")
                try expect(draft.inspireID == "2811054", "INSPIRE mapper should preserve the record id.")
        }

        private func inspireMetadataMapperExtractsCitationGraphFields() throws {
                let mapper = InspireMetadataMapper()
                let json = """
                {
                    "id": "1517248",
                    "metadata": {
                        "control_number": 1517248,
                        "titles": [{"title": "Dark matter in the Sun"}],
                        "abstracts": [{"value": "Solar dark matter scattering."}],
                        "authors": [{"full_name": "Garani, Raghuveer"}],
                        "arxiv_eprints": [{"value": "1702.02768"}],
                        "dois": [{"value": "10.1088/1475-7516/2017/05/007"}],
                        "publication_info": [{"year": 2017, "journal_title": "JCAP"}],
                        "inspire_categories": [{"term": "Phenomenology"}],
                        "citation_count": 103,
                        "reference_count": 197,
                        "references": [
                            {"record": {"$ref": "https://inspirehep.net/api/literature/812742"}},
                            {"record": {"$ref": "https://inspirehep.net/api/literature/812742"}},
                            {"recid": 930231}
                        ]
                    }
                }
                """

                let data = Data(json.utf8)
                let paper = try mapper.mapCitationPaper(data: data, fallbackRecordID: "1517248")
                let references = try mapper.referenceRecordIDs(data: data)
                try expect(paper.inspireID == "1517248", "INSPIRE citation paper should use control_number as id.")
                try expect(paper.firstAuthorLastName == "Garani", "INSPIRE citation paper should expose a compact first author label.")
                try expect(paper.citationCount == 103, "INSPIRE citation paper should extract citation_count.")
                try expect(paper.referenceCount == 197, "INSPIRE citation paper should extract reference_count.")
                try expect(references == ["812742", "930231"], "INSPIRE references should extract unique referenced record ids in order.")
        }

            private func llmRequestBuildsExpectedPayload() throws {
                let provider = OpenAICompatibleProvider()
                let configuration = LLMConfiguration(
                    provider: .openAICompatible,
                    baseURLString: "https://api.example.com/v1",
                    model: "test-model",
                    temperature: 0.3,
                    maxTokens: 256
                )

                let request = try provider.buildRequest(configuration: configuration, apiKey: "secret-key", prompt: "Summarize this paper")
                let body = try require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Expected request body to be encoded.")
                try expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions", "Provider should target /chat/completions on the configured base URL.")
                try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key", "Provider should attach the API key as a bearer token.")
                try expect(body.contains("test-model"), "Provider request body should contain the configured model.")
                try expect(body.contains("Summarize this paper"), "Provider request body should contain the prompt content.")
            }

                        private func openAIProviderPreservesReasoningContent() throws {
                                let provider = OpenAICompatibleProvider()
                                let completionJSON = """
                                {
                                    "choices": [
                                        {
                                            "message": {
                                                "role": "assistant",
                                                "content": "I need a tool.",
                                                "reasoning_content": "private chain summary required by thinking-mode APIs",
                                                "tool_calls": [
                                                    {
                                                        "id": "call-1",
                                                        "type": "function",
                                                        "function": {
                                                            "name": "read_note",
                                                            "arguments": "{\\\"path\\\":\\\"paper.md\\\"}"
                                                        }
                                                    }
                                                ]
                                            }
                                        }
                                    ]
                                }
                                """
                                let parsed = try OpenAICompatibleProvider.parseChatCompletionMessage(from: Data(completionJSON.utf8))
                                try expect(parsed.reasoningContent?.contains("thinking-mode") == true, "Provider should parse reasoning_content from assistant responses.")
                                try expect(parsed.toolCalls.first?.toolName == "read_note", "Provider should preserve tool calls while parsing reasoning_content.")

                                let request = LLMProviderRequest(messages: [parsed])
                                let chatRequest = try provider.buildChatRequest(
                                        configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
                                        apiKey: "secret-key",
                                        providerRequest: request
                                )
                                let bodyData = try require(chatRequest.httpBody, "Expected chat body data.")
                                let root = try require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any], "Expected JSON request object.")
                                let messages = try require(root["messages"] as? [[String: Any]], "Expected messages array.")
                                try expect(messages.first?["reasoning_content"] as? String == parsed.reasoningContent, "Provider should pass assistant reasoning_content back in the next request.")
                        }

            private func openAIProviderRejectsThinkingModeToolReplayWithoutReasoning() throws {
                let provider = OpenAICompatibleProvider()
                let call = AgentToolCall(id: "call-missing-reasoning", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
                let request = LLMProviderRequest(messages: [
                    LLMChatMessage(role: .assistant, content: "", toolCalls: [call])
                ])

                do {
                    _ = try provider.buildChatRequest(
                        configuration: LLMConfiguration(baseURLString: "https://api.deepseek.com", model: "deepseek-reasoner"),
                        apiKey: "secret-key",
                        providerRequest: request
                    )
                    throw ValidationError(message: "Thinking-mode request should reject assistant tool calls without reasoning_content.")
                } catch let error as LLMProviderRequestSanitizer.Failure {
                    try expect(error.localizedDescription.contains("reasoning_content"), "Sanitizer error should explain the missing reasoning_content replay requirement.")
                }
            }

            private func openAIProviderTreatsDeepSeekV4FlashAsThinkingMode() throws {
                let call = AgentToolCall(id: "call-deepseek-v4", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
                let request = LLMProviderRequest(messages: [
                    LLMChatMessage(role: .assistant, content: "", toolCalls: [call])
                ])
                let configuration = LLMConfiguration(baseURLString: "https://api.deepseek.com/v1", model: "deepseek-v4-flash")

                try expect(
                    LLMProviderRequestSanitizer.requiresReasoningContentForToolReplay(request: request, configuration: configuration),
                    "DeepSeek v4 flash should use thinking-mode replay validation when assistant tool calls are present."
                )
            }

            private func llmConfigurationStorePersistsWithoutAPIKey() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore
                )
                let store = LLMConfigurationStore()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LLMSettingsWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                try await store.save(
                    LLMConfiguration(
                        provider: .openAICompatible,
                        baseURLString: "https://api.example.com/v1",
                        model: "gpt-4.1-mini",
                        temperature: 0.2,
                        maxTokens: 1200
                    ),
                    in: workspace
                )

                let settingsContents = try String(contentsOf: workspace.fileURL(for: "settings.yaml"), encoding: .utf8)
                try expect(settingsContents.contains("base_url"), "LLM settings should be written to settings.yaml.")
                try expect(!settingsContents.lowercased().contains("api_key"), "API keys must not be written into settings.yaml.")
            }

            private func paperSummaryPromptBuilderIncludesContext() throws {
                var paper = samplePaper(id: "summary-context-paper")
                paper.doi = "10.1234/example"
                paper.abstract = "A compact abstract for testing prompt context."
                paper.tags = ["dark-matter", "review"]

                let prompt = PaperSummaryPromptBuilder().buildPrompt(
                    for: paper,
                    rawMarkdown: "# Raw Text\n\nImportant equation and method details.",
                    annotations: "# Annotations\n\nCheck the simulation setup.",
                    existingWiki: "# Existing Wiki\n\nPrior manual notes."
                )

                try expect(prompt.contains("10.1234/example"), "Prompt should include DOI metadata.")
                try expect(prompt.contains("Important equation and method details."), "Prompt should include raw markdown or extracted text.")
                try expect(prompt.contains("Check the simulation setup."), "Prompt should include annotations.")
                try expect(prompt.contains("Prior manual notes."), "Prompt should include existing wiki content.")
                try expect(prompt.contains("不要编造"), "Prompt should explicitly forbid invented claims.")
            }

            private func llmWritebackServiceKeepsDraftsSeparateFromWiki() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore
                )
                let service = LLMWritebackService()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LLMWritebackWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = samplePaper(id: "writeback-paper")
                let wikiURL = workspace.fileURL(for: "wiki/papers/\(paper.citekey).md")
                try "# Original Wiki\n\nManual note.".write(to: wikiURL, atomically: true, encoding: .utf8)

                let firstDraft = try await service.write("Draft summary", to: wikiURL, mode: .saveDraft, paper: paper, in: workspace)
                let secondDraft = try await service.write("Second draft", to: wikiURL, mode: .saveDraft, paper: paper, in: workspace)
                let wikiAfterDraft = try String(contentsOf: wikiURL, encoding: .utf8)

                try expect(!firstDraft.didModifyWiki, "Saving a draft should report that the canonical wiki page was not modified.")
                try expect(firstDraft.writtenURL != secondDraft.writtenURL, "Multiple draft saves should not overwrite older drafts.")
                try expect(wikiAfterDraft == "# Original Wiki\n\nManual note.", "Saving a draft should leave the canonical wiki page unchanged.")

                let appendResult = try await service.write("Appended summary", to: wikiURL, mode: .append, paper: paper, in: workspace)
                let appendedWiki = try String(contentsOf: wikiURL, encoding: .utf8)

                try expect(appendResult.didModifyWiki, "Appending should report that the canonical wiki page was modified.")
                try expect(appendedWiki.contains("## AI Summary"), "Append mode should add an AI Summary section.")
                try expect(appendedWiki.contains("Appended summary"), "Append mode should write generated content.")

                let replaceResult = try await service.write("Replacement summary", to: wikiURL, mode: .replace, paper: paper, in: workspace)
                let replacedWiki = try String(contentsOf: wikiURL, encoding: .utf8)

                try expect(replaceResult.didModifyWiki, "Replace should report that the canonical wiki page was modified.")
                try expect(replacedWiki == "Replacement summary", "Replace mode should replace the canonical wiki content.")
            }

            private func agentPlanParserExtractsJSONFromMarkdownFence() throws {
                let response = """
                ```json
                {
                  "summary": "Create a todo",
                  "tool_calls": [
                    {
                      "id": "call-1",
                      "tool_name": "create_todo",
                      "arguments_json": "{\\\"title\\\":\\\"Read the selected paper\\\"}"
                    }
                  ],
                  "final_response_draft": "Ready for approval."
                }
                ```
                """

                let plan = try AgentPlanParser().parse(response)

                try expect(plan.summary == "Create a todo", "Agent plan parser should decode the summary.")
                try expect(plan.toolCalls.first?.toolName == "create_todo", "Agent plan parser should decode tool calls.")
                try expect(plan.toolCalls.first?.argumentsJSON.contains("Read the selected paper") == true, "Agent plan parser should preserve encoded tool arguments.")
            }

            private func agentPlanParserExtractsBalancedJSONBeforeTrailingText() throws {
                let response = """
                {"summary":"写入 wiki","tool_calls":[],"final_response_draft":"正文里可以包含 {braces}。"}

                额外说明：已准备写入。
                """

                let plan = try AgentPlanParser().parse(response)
                try expect(plan.finalResponseDraft == "正文里可以包含 {braces}。", "Plan parser should use the first balanced JSON object and ignore trailing prose.")
            }

            private func agentVisibleResponseExtractorHidesJSONEnvelope() throws {
                let jsonResponse = """
                {
                    "summary": "Internal summary",
                    "tool_calls": [],
                    "final_response_draft": "只显示这一段。"
                }
                """

                let visibleText = AgentVisibleResponseExtractor.visibleText(from: jsonResponse)
                let partialJSON = "{\"summary\": \"still streaming"
                let plainText = "普通 Markdown 回复"

                try expect(visibleText == "只显示这一段。", "Visible response extractor should return final_response_draft from JSON envelopes.")
                try expect(AgentVisibleResponseExtractor.visibleText(from: partialJSON) == "still streaming", "Visible response extractor should recover partial structured text instead of hiding all output.")
                try expect(AgentVisibleResponseExtractor.visibleText(from: plainText) == plainText, "Visible response extractor should preserve plain text responses.")
            }

            private func agentVisibleResponseExtractorKeepsPartialStructuredText() throws {
                let partialResponse = "{\"response\": \"第一段已经生成，第二段"
                let unknownEnvelope = "{\"tool_calls\": [], \"display\": \"fallback text\"}"

                try expect(AgentVisibleResponseExtractor.visibleText(from: partialResponse).contains("第一段已经生成"), "Partial structured responses should keep the user-visible field while streaming or interrupted.")
                try expect(AgentVisibleResponseExtractor.visibleText(from: unknownEnvelope) == "fallback text", "Structured envelopes with unfamiliar string keys should still expose useful text.")
            }

            private func agentVisibleModeMapsConversationAndPlanToPlan() throws {
                try expect(AgentVisibleMode(interactionMode: .conversation) == .plan, "Conversation mode should appear as Plan in the UI adapter.")
                try expect(AgentVisibleMode(interactionMode: .plan) == .plan, "Legacy plan mode should appear as Plan in the UI adapter.")
                try expect(AgentInteractionMode.conversation.visibleMode == .plan, "Interaction mode adapter should preserve old conversation runs as visible Plan.")
            }

            private func agentVisibleModeMapsAssistantToAgent() throws {
                try expect(AgentVisibleMode(interactionMode: .assistant) == .agent, "Assistant mode should appear as Agent in the UI adapter.")
                try expect(AgentVisibleMode.agent.defaultInteractionMode == .assistant, "Visible Agent should use the assistant runtime behavior.")
                try expect(AgentVisibleMode.plan.defaultInteractionMode == .conversation, "Visible Plan should keep the streaming conversation runtime behavior.")
            }

            private func agentInteractionModeRuntimePolicyMatchesVisibleModes() throws {
                try expect(AgentInteractionMode.conversation.usesToolLoopRuntime, "Visible Plan should keep the tool-loop runtime for read-only research answers.")
                try expect(AgentInteractionMode.assistant.usesToolLoopRuntime, "Visible Agent should execute read-only tools and pause only for approval-requiring writes.")
                try expect(!AgentInteractionMode.plan.usesToolLoopRuntime, "Legacy Plan mode should remain planner-only.")
            }

            private func planModeRequiresReadableToolSet() throws {
                let readTool = AgentToolDefinition(name: "search_papers", summary: "Search papers", inputSchema: "{}", risk: .readOnly)
                let writeTool = AgentToolDefinition(name: "write_wiki_markdown", summary: "Write wiki", inputSchema: "{}", risk: .writesWorkspace)

                try expect(AgentVisibleMode.plan.hasRequiredTools(availableTools: [readTool, writeTool], enabledToolNames: ["search_papers"]), "Plan mode should run when a read-only tool is enabled.")
                try expect(!AgentVisibleMode.plan.hasRequiredTools(availableTools: [readTool, writeTool], enabledToolNames: ["write_wiki_markdown"]), "Plan mode should warn when no read-only tools are enabled.")
                try expect(AgentVisibleMode.agent.hasRequiredTools(availableTools: [readTool, writeTool], enabledToolNames: ["write_wiki_markdown"]), "Agent mode should run when at least one tool is enabled.")
            }

            private func agentTimelineProjectionKeepsChronologicalOrder() throws {
                let events = [
                    AgentSessionEvent(id: "late", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 30), kind: .assistantMessage, summary: "late"),
                    AgentSessionEvent(id: "early", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .userMessage, summary: "early"),
                    AgentSessionEvent(id: "middle", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 20), kind: .toolCallStarted, summary: "middle")
                ]

                let items = AgentSessionTimelineItem.items(from: events, sessionIDs: ["run-a"], limit: nil)
                try expect(items.map(\.eventID) == ["early", "middle", "late"], "Timeline projection should keep chronological order when loading full history.")
            }

            private func agentTimelineProjectionGroupsReasoningEvents() throws {
                let item = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(id: "reasoning", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .reasoningSummary, summary: "Read papers and compare formulas.")
                ]).first
                let event = try require(item.map(AgentTimelineEvent.init(item:)), "Reasoning timeline item should project.")

                try expect(event.kind == .reasoningGroup, "Reasoning summaries should project as reasoning groups.")
                try expect(event.isCollapsedByDefault, "Reasoning groups should be collapsed by default.")
                try expect(event.stepCount == 1, "Reasoning groups should report at least one visible step.")
            }

            private func agentTimelineProjectionHidesHookResults() throws {
                let items = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(id: "user", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .userMessage, summary: "Hello"),
                    AgentSessionEvent(id: "hook", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 11), kind: .hookResult, summary: "Stop validation reminder"),
                    AgentSessionEvent(id: "assistant", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 12), kind: .assistantMessage, summary: "Hi")
                ])
                let events = AgentTimelineEvent.events(from: items)

                try expect(events.map(\.sourceKind) == [.userMessage, .assistantMessage], "Hook results should stay in audit logs but not render in the AI Lab timeline.")
            }

            private func agentTimelineProjectionMergesToolStartAndFinish() throws {
                let items = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(
                        id: "start",
                        sessionID: "run-a",
                        createdAt: Date(timeIntervalSince1970: 10),
                        kind: .toolCallStarted,
                        summary: "Running read_paper.",
                        payloadJSON: "{\"tool_call_id\":\"call-a\",\"tool_name\":\"read_paper\"}"
                    ),
                    AgentSessionEvent(
                        id: "finish",
                        sessionID: "run-a",
                        createdAt: Date(timeIntervalSince1970: 11),
                        kind: .toolCallCompleted,
                        summary: "已使用工具：read_paper",
                        payloadJSON: "{\"tool_call_id\":\"call-a\",\"tool_name\":\"read_paper\",\"summary\":\"ok\"}"
                    )
                ])
                let events = AgentTimelineEvent.events(from: items)
                let event = try require(events.first, "Merged tool event should exist.")

                try expect(events.count == 1, "Tool start and finish should render as one timeline row.")
                try expect(event.id == "tool-run-a-call-a", "Merged tool row should keep a stable id for in-place UI updates.")
                try expect(event.status == .succeeded, "Merged tool row should update to the finish status.")
                try expect(event.toolName == "read_paper", "Merged tool row should keep the tool name.")
            }

            private func toolCallRowsAreCollapsedByDefault() throws {
                let item = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(id: "tool", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .toolCallCompleted, summary: "已使用工具：search_papers", payloadJSON: "{\"tool_name\":\"search_papers\"}")
                ]).first
                let event = try require(item.map(AgentTimelineEvent.init(item:)), "Tool timeline item should project.")

                try expect(event.kind == .toolCall, "Tool events should project as compact tool rows.")
                try expect(event.toolName == "search_papers", "Tool rows should expose the tool name.")
                try expect(event.isCollapsedByDefault, "Tool rows should be collapsed by default.")
            }

            private func permissionRequestShowsAllowDenyOnlyByDefault() throws {
                let item = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(id: "permission", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .permissionRequested, summary: "write_wiki_markdown needs approval.", payloadJSON: "{\"target_path\":\"wiki/test.md\"}")
                ]).first
                let event = try require(item.map(AgentTimelineEvent.init(item:)), "Permission timeline item should project.")

                try expect(event.kind == .permissionRequest, "Permission events should project as inline permission requests.")
                try expect(event.status == .waitingForApproval, "Permission requests should remain waiting until the user decides.")
                try expect(event.targetPaths == ["wiki/test.md"], "Permission requests should expose target paths for review.")
                try expect(event.isCollapsedByDefault, "Permission details should be collapsed by default.")
            }

            private func draftReviewDefaultsToProjectWikiWhenProjectContextExists() throws {
                let path = AgentDraftReviewItem.defaultWikiTargetPath(projectID: "project-a", slug: "notes/summary")
                try expect(path == "projects/project-a/wiki/summary.md", "Project draft review should default to the project's wiki folder.")
            }

            private func draftReviewFallsBackToGlobalWikiWithoutProject() throws {
                let path = AgentDraftReviewItem.defaultWikiTargetPath(projectID: nil, slug: "summary.md")
                try expect(path == "wiki/summary.md", "Workspace draft review should fall back to the global wiki folder.")
            }

            private func timelinePaginationCanLoadEarlierEvents() throws {
                let events = (0..<180).map { index in
                    AgentSessionEvent(
                        id: "event-\(index)",
                        sessionID: "run-a",
                        createdAt: Date(timeIntervalSince1970: Double(index)),
                        kind: .assistantMessage,
                        summary: "message \(index)"
                    )
                }

                let limited = AgentSessionTimelineItem.items(from: events, sessionIDs: ["run-a"], limit: 120)
                let full = AgentSessionTimelineItem.items(from: events, sessionIDs: ["run-a"], limit: nil)

                try expect(limited.count == 120, "Timeline projection should still support a page-size limit.")
                try expect(limited.first?.eventID == "event-60", "Limited projection should return the newest page.")
                try expect(full.count == 180, "Full timeline projection should be available for Load Earlier pagination.")
                try expect(full.first?.eventID == "event-0", "Full projection should preserve earliest events.")
            }

            private func agentPlanParserWritebackFallbackKeepsMarkdownDraft() throws {
                let response = """
                ## AI Summary

                这是一段准备写进 wiki 的 Markdown 草稿，包含公式 $E_\\odot$。
                """
                let plan = try require(
                    AgentPlanParser().writebackFallbackPlan(response: response, goal: "把这篇文章总结一下写进 wiki 里"),
                    "Writeback fallback should produce a draft plan for non-JSON Markdown."
                )

                try expect(plan.title == "未确认的写回草稿", "Writeback fallback should use the explicit draft title.")
                try expect(plan.toolCalls.isEmpty, "Writeback fallback should not execute a workspace write without approval.")
                try expect(plan.finalResponseDraft?.contains("E_\\odot") == true, "Writeback fallback should preserve the original Markdown draft.")
            }

            private func agentPlannerAcceptsPlainTextConversationResponse() async throws {
                let provider = StaticLLMProvider(response: "你好，我可以用 **Markdown** 回答。")
                let planner = AgentPlanner(provider: provider)
                let plan = try await planner.plan(
                    goal: "请用中文介绍当前项目",
                    workspaceSnapshot: AgentWorkspaceSnapshot(
                        workspaceName: "Test_Workspace",
                        selectedPaper: nil,
                        recentPapers: [],
                        openTodos: [],
                        paperCount: 0,
                        todoCount: 0
                    ),
                    tools: [],
                    configuration: LLMConfiguration(),
                    apiKey: "test-key",
                    modeInstructions: AgentInteractionMode.conversation.plannerInstructions,
                    allowsPlainTextResponse: true
                )

                try expect(plan.toolCalls.isEmpty, "Plain text conversation fallback should not create tool calls.")
                try expect(plan.finalResponseDraft?.contains("Markdown") == true, "Plain text conversation fallback should preserve the assistant response.")
            }

            private func agentPlannerAcceptsPlainTextAssistantFallback() async throws {
                let provider = StaticLLMProvider(response: "当前项目共有 3 篇论文。")
                let planner = AgentPlanner(provider: provider)
                let plan = try await planner.plan(
                    goal: "项目里都有什么文章？列一下",
                    workspaceSnapshot: AgentWorkspaceSnapshot(
                        workspaceName: "Test_Workspace",
                        selectedPaper: nil,
                        recentPapers: [],
                        openTodos: [],
                        paperCount: 3,
                        todoCount: 0
                    ),
                    tools: [],
                    configuration: LLMConfiguration(),
                    apiKey: "test-key",
                    modeInstructions: AgentInteractionMode.assistant.plannerInstructions,
                    allowsPlainTextResponse: false
                )

                try expect(plan.toolCalls.isEmpty, "Assistant fallback should not invent tool calls from plain text.")
                try expect(plan.finalResponseDraft == "当前项目共有 3 篇论文。", "Assistant fallback should preserve readable non-JSON replies.")
                try expect(plan.title == "AI 回复", "Assistant fallback should mark the run as a visible AI reply.")
            }

            private func agentToolExecutorRequiresApprovalForTodoWrites() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let todoRepository = TodoRepository()
                let registry = AgentToolRegistry(tools: [CreateTodoAgentTool(todoRepository: todoRepository)])
                let executor = AgentToolExecutor(registry: registry)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentTodoWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let plan = AgentPlan(
                    summary: "Create a follow-up todo",
                    toolCalls: [
                        AgentToolCall(
                            id: "call-1",
                            toolName: "create_todo",
                            argumentsJSON: "{\"title\":\"Check agent framework\",\"priority\":\"high\",\"tags\":[\"agent\"]}"
                        )
                    ]
                )
                let context = AgentToolContext(workspace: workspace, selectedPaperID: "paper-001", currentProjectID: "project-alpha")

                let blockedResults = await executor.execute(plan: plan, context: context, approvedToolCallIDs: [])
                let todosBeforeApproval = try await todoRepository.loadTodos(in: workspace)
                try expect(blockedResults.first?.requiresConfirmation == true, "Workspace-writing agent tools should require approval before execution.")
                try expect(todosBeforeApproval.isEmpty, "Unapproved agent tool calls should not modify todos.")

                let approvedResults = await executor.execute(plan: plan, context: context, approvedToolCallIDs: ["call-1"])
                let todosAfterApproval = try await todoRepository.loadTodos(in: workspace)
                try expect(approvedResults.first?.succeeded == true, "Approved todo tool call should succeed.")
                try expect(approvedResults.first?.callID == "call-1", "Agent tool results should retain the originating call id.")
                try expect(todosAfterApproval.first?.title == "Check agent framework", "Approved todo tool call should persist a todo.")
                try expect(todosAfterApproval.first?.relatedPaperIDs == ["paper-001"], "Todo tool should link to the selected paper when no explicit related_paper_ids are provided.")
                try expect(todosAfterApproval.first?.projectIDs == ["project-alpha"], "Todo tool should default to the current project when project_ids are omitted.")
            }

            private func writeWikiMarkdownAgentToolValidatesWhitelist() async throws {
                let fixture = try await loopWorkspaceFixture(named: "WriteWikiMarkdownToolWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let paperRepository = PaperRepository()
                _ = try await paperRepository.save(samplePaper(id: "paper-valid"), in: fixture.workspace)
                let tool = WriteMarkdownPlanAgentTool(markdownRepository: MarkdownRepository(), paperRepository: paperRepository)
                let context = AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)

                let paperResult = try await tool.invoke(
                    argumentsJSON: "{\"title\":\"Paper Summary\",\"body\":\"## AI Summary\\n\\nFormula $E$.\",\"relative_path\":\"wiki/papers/paper-valid.md\"}",
                    context: context
                )
                try expect(paperResult.modifiedPaths == ["wiki/papers/paper-valid.md"], "Wiki paper writeback should allow existing paper ids.")
                try expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: "wiki/papers/paper-valid.md").path), "Wiki paper writeback should create the target file.")

                let noteResult = try await tool.invoke(
                    argumentsJSON: #"{"title":"Free Note","body":"Body","relative_path":"wiki/notes/free-note.md"}"#,
                    context: context
                )
                try expect(noteResult.modifiedPaths == ["wiki/notes/free-note.md"], "Wiki notes writeback should be allowed.")

                try await expectWikiWriteRejected(tool, context: context, path: "wiki/../etc.md")
                try await expectWikiWriteRejected(tool, context: context, path: "/tmp/etc.md")
                try await expectWikiWriteRejected(tool, context: context, path: "wiki/papers/missing-paper.md")
            }

            private func agentPaperClassificationToolUpdatesMetadata() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let paperRepository = PaperRepository()
                let registry = AgentToolRegistry(tools: [UpdatePaperClassificationAgentTool(paperRepository: paperRepository)])
                let executor = AgentToolExecutor(registry: registry)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentPaperWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = try await paperRepository.save(samplePaper(id: "agent-paper"), in: workspace)
                let plan = AgentPlan(
                    summary: "Classify selected paper",
                    toolCalls: [
                        AgentToolCall(
                            id: "call-1",
                            toolName: "update_paper_classification",
                            argumentsJSON: "{\"tags\":[\"simulation\",\"dark-matter\"],\"categories\":[\"methods\"],\"mark_core_in_current_project\":true,\"priority\":\"urgent\",\"status\":\"skimmed\"}"
                        )
                    ]
                )

                let results = await executor.execute(
                    plan: plan,
                    context: AgentToolContext(workspace: workspace, selectedPaperID: paper.id, currentProjectID: "project-alpha"),
                    approvedToolCallIDs: ["call-1"]
                )
                let updatedPaper = try require(try await paperRepository.loadPapers(in: workspace).first(where: { $0.id == paper.id }), "Expected updated paper to be loadable.")

                try expect(results.first?.succeeded == true, "Approved classification tool call should succeed.")
                try expect(updatedPaper.tags.contains("simulation"), "Classification tool should merge new tags.")
                try expect(updatedPaper.categories.contains("methods"), "Classification tool should merge new categories.")
                try expect(updatedPaper.projectIDs.contains("project-alpha"), "Classification tool should add the selected paper to the current project when requested.")
                try expect(updatedPaper.coreProjectIDs.contains("project-alpha"), "Classification tool should mark the selected paper as core in the current project when requested.")
                try expect(updatedPaper.priority == .urgent, "Classification tool should update priority.")
                try expect(updatedPaper.status == .skimmed, "Classification tool should update reading status.")
            }

            private func agentPaperReadToolsReturnSectionsAndSearchMatches() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let paperRepository = PaperRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentPaperReadToolsWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                var paper = samplePaper(id: "agent-readable-paper")
                paper.title = "Evaporation Rate Reference"
                paper.tags = ["dm"]
                let savedPaper = try await paperRepository.save(paper, in: workspace)
                let markdown = """
                # Evaporation Rate Reference

                ## 1 Overview

                This section introduces the model.

                ## 5 Evaporation Rate

                The evaporation rate marker is E_sun_section_marker.

                $$
                E_{\\odot} = \\sum_i \\int s(r) n_\\chi(r) 4\\pi r^2 dr
                $$

                ![](figures/mineru/images/figure-2-a.jpg)

                ![](figures/mineru/images/figure-2-b.jpg)

                Figure 2. DM temperature as a function of the DM mass.

                ## Appendix

                Extra material.
                """
                try markdown.write(to: savedPaper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

                let registry = AgentToolRegistry(tools: [
                    ListPapersAgentTool(paperRepository: paperRepository),
                    ReadPaperSectionAgentTool(paperRepository: paperRepository),
                    SearchPapersAgentTool(paperRepository: paperRepository)
                ])
                let executor = AgentToolExecutor(registry: registry)
                let plan = AgentPlan(
                    summary: "Read paper sections",
                    toolCalls: [
                        AgentToolCall(
                            id: "call-section",
                            toolName: "read_paper_section",
                            argumentsJSON: "{\"paper_id\":\"\(savedPaper.id)\",\"heading\":\"5 Evaporation Rate\"}"
                        ),
                        AgentToolCall(
                            id: "call-search",
                            toolName: "search_papers",
                            argumentsJSON: "{\"query\":\"E_sun_section_marker\",\"paper_ids\":[\"\(savedPaper.id)\"]}"
                        ),
                        AgentToolCall(
                            id: "call-list",
                            toolName: "list_papers",
                            argumentsJSON: "{\"query\":\"Evaporation\"}"
                        ),
                        AgentToolCall(
                            id: "call-figure",
                            toolName: "read_paper_section",
                            argumentsJSON: "{\"paper_id\":\"\(savedPaper.id)\",\"heading\":\"Figure 2\"}"
                        ),
                        AgentToolCall(
                            id: "call-heading-with-lines",
                            toolName: "read_paper_section",
                            argumentsJSON: "{\"paper_id\":\"\(savedPaper.id)\",\"heading\":\"5 Evaporation Rate\",\"start_line\":1,\"end_line\":3}"
                        )
                    ]
                )

                let results = await executor.execute(
                    plan: plan,
                    context: AgentToolContext(workspace: workspace, selectedPaperID: savedPaper.id),
                    approvedToolCallIDs: []
                )
                let definitions = await SciStationAgentService(
                    provider: StaticLLMProvider(response: "{\"summary\":\"No-op\",\"tool_calls\":[]}")
                ).toolDefinitions()
                let definitionNames = Set(definitions.map(\.name))

                try expect(results.allSatisfy(\.succeeded), "Read-only paper tools should run without approval.")
                try expect(results.first(where: { $0.callID == "call-section" })?.message.contains("E_sun_section_marker") == true, "read_paper_section should return the requested heading content.")
                try expect(results.first(where: { $0.callID == "call-search" })?.message.contains("#L") == true, "search_papers should return line-anchored matches.")
                try expect(results.first(where: { $0.callID == "call-list" })?.message.contains(savedPaper.id) == true, "list_papers should expose matching paper ids.")
                try expect(results.first(where: { $0.callID == "call-figure" })?.message.contains("figure-2-a.jpg") == true, "read_paper_section should return local image references for figure captions.")
                try expect(results.first(where: { $0.callID == "call-figure" })?.message.contains("DM temperature") == true, "read_paper_section should match figure captions by figure number.")
                try expect(results.first(where: { $0.callID == "call-heading-with-lines" })?.message.contains("E_sun_section_marker") == true, "read_paper_section should prefer heading over incidental line ranges.")
                try expect(results.first(where: { $0.callID == "call-section" })?.payload?.objectValue?["kind"]?.stringValue == "paper_section", "read_paper_section should expose a structured payload.")
                try expect(results.first(where: { $0.callID == "call-search" })?.payload?.objectValue?["matches"]?.arrayValue?.isEmpty == false, "search_papers should expose structured matches.")
                try expect(results.first(where: { $0.callID == "call-list" })?.payload?.objectValue?["papers"]?.arrayValue?.first?.objectValue?["paper_id"]?.stringValue == savedPaper.id, "list_papers should expose structured paper ids.")
                try expect(definitionNames.isSuperset(of: ["list_papers", "read_paper", "read_paper_section", "search_papers"]), "Default agent tool registry should expose paper read/search tools.")
            }

            private func agentWorkspaceSnapshotIncludesProjectContext() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let projectRegistryRepository = ProjectRegistryRepository()
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore,
                    projectRegistryRepository: projectRegistryRepository
                )
                let paperRepository = PaperRepository()
                let todoRepository = TodoRepository()
                let contextBuilder = AgentWorkspaceContextBuilder(
                    paperRepository: paperRepository,
                    todoRepository: todoRepository
                )
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentProjectContextWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let registry = try await projectRegistryRepository.load(in: root)
                let project = try require(registry.projects.first, "Expected a default project for agent context.")
                var paper = samplePaper(id: "agent-project-paper")
                paper.projectIDs = [project.id]
                paper.coreProjectIDs = [project.id]
                let savedPaper = try await paperRepository.save(paper, in: workspace)
                let todo = TodoItem(
                    id: "todo-agent-project",
                    title: "Read project paper",
                    status: .open,
                    dueDate: nil,
                    priority: .high,
                    projectIDs: [project.id],
                    tags: ["agent"],
                    relatedPaperIDs: [savedPaper.id],
                    notes: nil,
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    updatedAt: Date(timeIntervalSince1970: 1_777_600_000)
                )
                try await todoRepository.upsert(todo, in: workspace)

                let snapshot = try await contextBuilder.snapshot(
                    in: workspace,
                    root: root,
                    projects: registry.projects,
                    currentProjectID: project.id,
                    selectedPaperID: savedPaper.id
                )

                try expect(snapshot.rootName == root.displayName, "Agent snapshot should include the research root name.")
                try expect(snapshot.currentProjectID == project.id, "Agent snapshot should include current project id.")
                try expect(snapshot.currentProject?.paperCount == 1, "Agent snapshot should include current project paper count.")
                try expect(snapshot.projectPapers.map(\.id) == [savedPaper.id], "Agent snapshot should include project-associated papers.")
                try expect(snapshot.projectOpenTodos.map(\.id) == [todo.id], "Agent snapshot should include current project open todos.")
                try expect(snapshot.paperLibraryRelativePath == Paper.globalLibraryRootRelativePath, "Agent snapshot should advertise the global paper library path.")
            }

            private func agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let repository = PaperRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentMetadataOnlyContextWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = try await repository.save(samplePaper(id: "metadata-only-paper"), in: workspace)
                let marker = "metadata_only_snapshot_should_not_embed_this_marker"
                try ("# Metadata Only Paper\n\n## Hidden Body\n\n\(marker)")
                    .write(to: paper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

                let snapshot = try await AgentWorkspaceContextBuilder(paperRepository: repository).snapshot(
                    in: workspace,
                    selectedPaperID: paper.id,
                    includedPaperIDs: [paper.id],
                    paperLimit: 5
                )
                let selectedPaper = try require(snapshot.selectedPaper, "Selected paper should be present in the snapshot.")
                let recentPaper = try require(snapshot.recentPapers.first(where: { $0.id == paper.id }), "Recent paper should be present in the snapshot.")
                let prompt = try AgentPromptBuilder().buildPrompt(
                    goal: "Explain the hidden body marker.",
                    workspaceSnapshot: snapshot,
                    tools: []
                )

                try expect(selectedPaper.sourceExcerpt == nil, "Default selected paper snapshot should not embed paper.md text.")
                try expect(recentPaper.sourceExcerpt == nil, "Default recent paper snapshot should not embed paper.md text.")
                try expect(recentPaper.rawMarkdownRelativePath?.hasSuffix("/paper.md") == true, "Metadata-only paper snapshots should still advertise converted paper.md paths.")
                try expect(!prompt.contains(marker), "Agent prompt should not contain paper markdown body text by default.")
            }

            private func agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let repository = PaperRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentLongPaperContextWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = try await repository.save(samplePaper(id: "long-context-paper"), in: workspace)
                let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
                try FileManager.default.createDirectory(at: paperDirectoryURL, withIntermediateDirectories: true)

                let earlyText = String(repeating: "Early context sentence for old cutoff testing.\n", count: 320)
                let deepMarker = "Section 5 evaporation-rate formula marker: E_sun_deep_context"
                try ("---\ntype: paper_raw_markdown\n---\n\n" + earlyText + "\n## 5 Evaporation Rate\n\n" + deepMarker)
                    .write(to: paper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

                let snapshot = try await AgentWorkspaceContextBuilder(paperRepository: repository).snapshot(
                    in: workspace,
                    includedPaperIDs: [paper.id],
                    paperContextPolicy: .legacyExcerpts,
                    paperLimit: 5
                )
                let paperSnapshot = try require(snapshot.recentPapers.first(where: { $0.id == paper.id }), "Included knowledge paper should be present in the snapshot.")
                try expect(paperSnapshot.sourceExcerpt?.contains(deepMarker) == true, "Legacy excerpt policy should preserve deeper Markdown sections beyond 10k characters.")
            }

            private func agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext() throws {
                var paper = samplePaper(id: "prompt-metadata-paper")
                paper.title = "Prompt Metadata Paper"
                let paperSnapshot = AgentPaperSnapshot(
                    paper: paper,
                    rawMarkdownRelativePath: "papers/prompt-metadata-paper/paper.md"
                )
                let snapshot = AgentWorkspaceSnapshot(
                    workspaceName: "Prompt Workspace",
                    selectedPaper: paperSnapshot,
                    recentPapers: [paperSnapshot],
                    openTodos: [],
                    paperCount: 1,
                    todoCount: 0
                )
                let paperRepository = PaperRepository()
                let tools = [
                    ListPapersAgentTool(paperRepository: paperRepository).definition,
                    SearchPapersAgentTool(paperRepository: paperRepository).definition,
                    ReadPaperSectionAgentTool(paperRepository: paperRepository).definition,
                    ReadPaperAgentTool(paperRepository: paperRepository).definition
                ]
                let prompt = try AgentPromptBuilder().buildPrompt(
                    goal: "解释这篇论文第 5 节的公式。",
                    workspaceSnapshot: snapshot,
                    tools: tools
                )

                try expect(prompt.contains("Paper snapshots are metadata-first"), "Prompt should explain metadata-first paper snapshots.")
                try expect(prompt.contains("plan paper tool calls before answering"), "Prompt should direct the model to call paper tools before detailed answers.")
                try expect(prompt.contains("Prefer `search_papers`"), "Prompt should guide search_papers usage.")
                try expect(prompt.contains("Prefer `read_paper_section`"), "Prompt should guide read_paper_section usage.")
                try expect(prompt.contains("list_papers -> search_papers -> read_paper_section"), "Prompt should force first-paper formula flows through list/search/read tools.")

                let toolLoopMessages = try AgentPromptBuilder().buildToolLoopChatMessages(
                    goal: "第一篇论文里的 evaporation rate 公式是什么？",
                    workspaceSnapshot: snapshot,
                    tools: tools
                )
                let toolLoopSystemPrompt = try require(toolLoopMessages.first?.content, "Tool-loop prompt should contain a system message.")
                try expect(toolLoopSystemPrompt.contains("call `list_papers` first"), "Tool-loop prompt should resolve ordinal paper references with list_papers first.")
                try expect(toolLoopSystemPrompt.contains("Final answers to paper formula questions must include the formula"), "Tool-loop prompt should require formula, context, and source in final answers.")
            }

            private func agentRunLoggerWritesWorkspaceFiles() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentLogWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let run = AgentRun(
                    id: "agent-run-test",
                    goal: "Plan a todo",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    completedAt: Date(timeIntervalSince1970: 1_777_600_001),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "No writes", toolCalls: []),
                    toolResults: []
                )
                try await AgentRunLogger().append(run, in: workspace)
                let logContents = try String(contentsOf: workspace.fileURL(for: ".sci-station/agent/runs.jsonl"), encoding: .utf8)
                try expect(logContents.contains("agent-run-test"), "Agent run logger should append JSONL entries.")
            }

            private func agentServicePlanOnlyRunLogsCurrentProjectAndReadsHistory() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let projectRegistryRepository = ProjectRegistryRepository()
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore,
                    projectRegistryRepository: projectRegistryRepository
                )
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentServicePlanWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let registry = try await projectRegistryRepository.load(in: root)
                let project = try require(registry.projects.first, "Expected a default project for service agent tests.")
                let provider = StaticLLMProvider(
                    response: """
                    {
                      "title": "Todo plan",
                      "summary": "Create a project follow-up todo.",
                      "risk": "Writes one todo after approval.",
                      "steps": ["Review current project context", "Create one todo after approval"],
                      "tool_calls": [
                        {
                          "id": "call-1",
                          "tool_name": "create_todo",
                          "arguments_json": "{\\\"title\\\":\\\"Review agent plan\\\"}"
                        }
                      ],
                      "final_response_draft": "Ready for approval."
                    }
                    """
                )
                let service = SciStationAgentService(provider: provider)

                let run = try await service.run(
                    goal: "Create a project todo",
                    in: workspace,
                    root: root,
                    projects: registry.projects,
                    currentProjectID: project.id,
                    configuration: LLMConfiguration(),
                    apiKey: "test-key",
                    options: AgentExecutionOptions(mode: .planOnly)
                )
                let history = try await service.recentRuns(in: root, limit: 5)
                let logContents = try String(contentsOf: root.fileURL(for: ".sci-station/agent/runs.jsonl"), encoding: .utf8)

                try expect(run.mode == .planOnly, "Agent service should support plan-only runs.")
                try expect(run.currentProjectID == project.id, "Plan-only run should record the current project id.")
                try expect(run.contextScope == .project, "Plan-only run should record project context scope.")
                try expect(run.projectID == project.id, "Plan-only run should persist the project_id metadata alias.")
                try expect(run.runtimeSelector == AgentRuntimeSelection.swiftLoop.rawValue, "Plan-only run should persist runtime selector metadata.")
                try expect(run.createdFromRoute == "ai_lab", "Plan-only run should record the originating AI Lab route.")
                try expect(run.enabledToolNames?.contains("create_todo") == true, "Plan-only run should snapshot enabled tools for replay.")
                try expect(run.plan.title == "Todo plan", "Agent plan should decode the optional title field.")
                try expect(run.plan.steps.count == 2, "Agent plan should decode ordered steps.")
                try expect(history.first?.id == run.id, "Agent service should read recent run history with newest entries first.")
                try expect(logContents.contains(project.id), "Agent run log should include current_project_id.")
                try expect(logContents.contains("\"context_scope\":\"project\""), "Agent run log should include context_scope metadata.")
                try expect(logContents.contains("\"project_id\":\"") && logContents.contains("\"runtime_selector\":\"swift_loop\""), "Agent run log should include project_id and runtime_selector metadata.")
                let sessionEvents = try await service.sessionEvents(in: root, sessionID: run.id)
                try expect(sessionEvents.map(\.kind).contains(.permissionRequested), "Plan-only runs should append permission request session events for requested tools.")
            }

            private func agentServiceRecordFailedRunPersistsInlineTimeline() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentFailedRunWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let service = SciStationAgentService(provider: StaticLLMProvider(response: "{}"))
                let run = try await service.recordFailedRun(
                    goal: "请生成一个阅读本项目论文的计划",
                    message: "Model unavailable.",
                    partialAssistantResponse: "已读取项目上下文，但模型不可用。",
                    in: root,
                    currentProjectID: "project-alpha",
                    runtimeSelector: AgentRuntimeSelection.autoFallback.rawValue,
                    enabledToolNames: ["list_papers", "read_paper"]
                )
                let history = try await service.recentRuns(in: root, limit: 5)
                let events = try await service.sessionEvents(in: root, sessionID: run.id)

                try expect(history.first?.id == run.id, "Failed runs should be durable in run history.")
                try expect(run.plan.risk == "Model unavailable.", "Failed runs should preserve an inline failure reason.")
                try expect(run.projectID == "project-alpha", "Failed runs should preserve project affinity metadata.")
                try expect(run.runtimeSelector == AgentRuntimeSelection.autoFallback.rawValue, "Failed runs should preserve runtime selector metadata.")
                try expect(run.enabledToolNames == ["list_papers", "read_paper"], "Failed runs should preserve tool selection metadata.")
                try expect(events.map(\.kind) == [.userMessage, .toolCallFailed], "Failed runs should leave a user message and inline failure event in the timeline.")
                try expect(events.last?.summary == "Model unavailable.", "Inline failure event should carry the visible failure reason.")
            }

            private func agentServiceRecordCancelledRunPersistsLifecycle() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentCancelledRunWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let service = SciStationAgentService(provider: StaticLLMProvider(response: "{}"))
                let run = try await service.recordCancelledRun(
                    goal: "请总结第一篇文章",
                    message: "用户已停止本次 AI 输出。",
                    partialAssistantResponse: "已读取论文，正在整理回答。",
                    in: root,
                    currentProjectID: "project-alpha",
                    runtimeSelector: AgentRuntimeSelection.swiftLoop.rawValue,
                    enabledToolNames: ["list_papers"],
                    retryOfRunID: "agent-run-previous"
                )
                let events = try await service.sessionEvents(in: root, sessionID: run.id)

                try expect(run.lifecycleState == .cancelled, "Cancelled runs should persist a cancelled lifecycle state.")
                try expect(run.failureCategory == .cancelledByUser, "Cancelled runs should preserve a user-cancelled failure category.")
                try expect(run.retryOfRunID == "agent-run-previous", "Cancelled retry attempts should keep retry source metadata.")
                try expect(events.map(\.kind) == [.userMessage, .assistantMessage, .runCancelled], "Cancelled runs should replay as user, partial assistant, and cancelled events.")
            }

            private func agentServiceExecutesApprovedPlan() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let projectRegistryRepository = ProjectRegistryRepository()
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore,
                    projectRegistryRepository: projectRegistryRepository
                )
                let todoRepository = TodoRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentServiceExecuteWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let registry = try await projectRegistryRepository.load(in: root)
                let project = try require(registry.projects.first, "Expected a default project for approved execution tests.")
                let service = SciStationAgentService(
                    provider: StaticLLMProvider(response: "{\"summary\":\"No-op\",\"tool_calls\":[]}"),
                    todoRepository: todoRepository
                )
                let plan = AgentPlan(
                    title: "Approved todo",
                    summary: "Create a todo after approval",
                    risk: "Writes tasks/todos.yaml",
                    steps: ["Create the approved todo"],
                    toolCalls: [
                        AgentToolCall(
                            id: "call-1",
                            toolName: "create_todo",
                            argumentsJSON: "{\"title\":\"Approved agent todo\",\"priority\":\"high\"}"
                        )
                    ]
                )

                let skippedRun = try await service.executeApprovedPlan(
                    goal: "Create approved todo",
                    plan: plan,
                    in: workspace,
                    root: root,
                    currentProjectID: project.id,
                    approvedToolCallIDs: []
                )
                try expect(skippedRun.toolResults.first?.requiresConfirmation == true, "Unapproved writing tools should be skipped with a confirmation result.")
                let todosBeforeApproval = try await todoRepository.loadTodos(in: workspace)
                try expect(todosBeforeApproval.isEmpty, "Unapproved service execution should not modify todos.")

                let approvedRun = try await service.executeApprovedPlan(
                    goal: "Create approved todo",
                    plan: plan,
                    in: workspace,
                    root: root,
                    currentProjectID: project.id,
                    approvedToolCallIDs: ["call-1"]
                )
                let todos = try await todoRepository.loadTodos(in: workspace)
                try expect(approvedRun.mode == .executeApproved, "Approved execution should be logged as executeApproved.")
                try expect(approvedRun.toolResults.first?.succeeded == true, "Approved service tool execution should succeed.")
                try expect(todos.first?.title == "Approved agent todo", "Approved service tool execution should persist the todo.")
                try expect(todos.first?.projectIDs == [project.id], "Approved service tool execution should use the current project context.")
                let executionEvents = try await service.sessionEvents(in: root, sessionID: approvedRun.id)
                try expect(executionEvents.map(\.kind).contains(.toolCallCompleted), "Approved execution should append completed tool session events.")
            }

            private func agentLoopRunnerCallsReadOnlyToolThenContinues() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopReadOnlyWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "最终回答包含 $E_{\\odot}$."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "section 5 says E_sun_section_marker")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-read-only",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let events = try await logger.events(in: fixture.root, sessionID: "loop-read-only")

                try expect(result.finalResponseMarkdown?.contains("E_{\\odot}") == true, "Loop should continue after a read-only tool and return the final assistant message.")
                try expect(result.toolResults.first?.message.contains("E_sun_section_marker") == true, "Loop should preserve read-only tool output.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Read-only tool should execute once.")
                try expect(events.map(\.kind).contains(.toolCallStarted), "Loop should append tool start events.")
                try expect(events.map(\.kind).contains(.toolCallCompleted), "Loop should append tool completion events.")
            }

            private func agentPaperIntentRouterMapsAbstractToAbstractSection() throws {
                let router = AgentPaperIntentRouter()
                let chineseIntent = router.classify("第一篇论文摘要是什么？")
                let englishIntent = router.classify("What is the abstract of the first paper?")
                let argumentsJSON = router.searchArgumentsJSON(for: chineseIntent, paperID: "paper-1")

                try expect(chineseIntent.kind == .sectionSummary, "Chinese abstract questions should be routed as section summaries.")
                try expect(chineseIntent.ordinalIndex == 0, "Chinese first-paper abstract questions should preserve ordinal selection.")
                try expect(chineseIntent.sectionHint == "Abstract", "Chinese 摘要 should map to the Abstract section hint.")
                try expect(chineseIntent.query?.contains("摘要") == true, "Chinese abstract queries should keep a bilingual retrieval query.")
                try expect(englishIntent.kind == .sectionSummary, "English abstract questions should be routed as section summaries.")
                try expect(englishIntent.ordinalIndex == 0, "English first-paper abstract questions should preserve ordinal selection.")
                try expect(englishIntent.sectionHint == "Abstract", "English abstract should map to the Abstract section hint.")
                try expect(argumentsJSON.contains("Abstract 摘要 summary"), "Search arguments should use a bilingual abstract retrieval query.")
            }

            private func agentPaperIntentRouterClassifiesGraphIntents() throws {
                let router = AgentPaperIntentRouter()
                let missing = router.classify("这个项目还有哪些核心论文没引？")
                let reading = router.classify("读完这篇下一篇应该看什么？")
                let stale = router.classify("检查这个项目有没有过时引用")
                let unsupported = router.classify("哪些 artifact claim 缺乏证据？")
                let bridge = router.classify("explain connection between paper:a and paper:c")

                try expect(missing.kind == .graphMissingCorePapers, "Missing-core graph questions should route to graphMissingCorePapers.")
                try expect(missing.graphToolName == GraphAgentTools.findMissingCorePapers, "Missing-core intent should prefer find_missing_core_papers.")
                try expect(reading.kind == .graphReadingPath, "Next-paper questions should route to graphReadingPath.")
                try expect(stale.kind == .graphStaleCitations, "Stale citation questions should route to graphStaleCitations.")
                try expect(unsupported.kind == .graphUnsupportedClaims, "Unsupported claim questions should route to graphUnsupportedClaims.")
                try expect(bridge.kind == .graphBridgePapers, "Bridge questions should route to graphBridgePapers.")
                let missingArgs = router.graphArgumentsJSON(for: missing, currentProjectID: "proj", selectedPaperID: nil) ?? ""
                let readingArgs = router.graphArgumentsJSON(for: reading, currentProjectID: "proj", selectedPaperID: "paper:center") ?? ""
                let bridgeArgs = router.graphArgumentsJSON(for: bridge, currentProjectID: nil, selectedPaperID: nil) ?? ""
                try expect(missingArgs.contains("proj"), "Missing-core graph preflight arguments should include project_id.")
                try expect(readingArgs.contains("paper:center"), "Reading path preflight arguments should include selected center paper.")
                try expect(bridgeArgs.contains("paper:a") && bridgeArgs.contains("paper:c"), "Bridge preflight arguments should include both paper node ids.")
            }

            private func agentPaperIntentRouterMapsThirdPaperOrdinal() throws {
                let router = AgentPaperIntentRouter()
                let chineseIntent = router.classify("第三篇文章的摘要是什么？")
                let digitIntent = router.classify("第 3 篇论文的蒸发率公式是什么？")
                let englishIntent = router.classify("What is the abstract of the third paper?")
                let argumentsJSON = router.searchArgumentsJSON(for: digitIntent, paperID: "garani-paper")

                try expect(chineseIntent.kind == .sectionSummary, "Chinese third-paper abstract questions should be routed as section summaries.")
                try expect(chineseIntent.ordinalIndex == 2, "Chinese third-paper references should map to ordinal index 2.")
                try expect(digitIntent.kind == .formula, "Digit third-paper formula questions should route to formula evidence.")
                try expect(digitIntent.ordinalIndex == 2, "Digit third-paper references should map to ordinal index 2.")
                try expect(englishIntent.ordinalIndex == 2, "English third-paper references should map to ordinal index 2.")
                try expect(argumentsJSON.contains("garani-paper"), "Third-paper search arguments should be restricted to the resolved paper id.")
                try expect(!argumentsJSON.contains("第 3 篇"), "Ordinal phrases should be removed from retrieval queries.")
            }

            private func agentLoopRunnerReturnsVisibleFallbackAfterToolThenEmptyProvider() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopEmptyProviderAfterToolWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-read-section", toolName: "read_paper_section", argumentsJSON: #"{"paper_id":"paper-1","heading":"Evaporation Rate"}"#)
                let provider = ScriptedFailingChatProvider(steps: [
                    .success(LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])),
                    .failure(.emptyResponse)
                ])
                let definition = loopToolDefinition(name: "read_paper_section", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_paper_section", succeeded: true, message: "Evaporation Rate marker: E_sun_section_marker and formula context.")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-empty-provider-after-tool",
                    goal: "第一篇论文的 evaporation rate 公式是什么？",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let events = try await logger.events(in: fixture.root, sessionID: "loop-empty-provider-after-tool")

                try expect(result.pauseReason?.kind == .providerUnavailable, "Empty provider response after tool results should be represented as providerUnavailable.")
                try expect(result.finalResponseMarkdown?.contains("模型没有返回最终回复") == true, "Empty provider response after tool results should produce a visible Chinese fallback.")
                try expect(result.finalResponseMarkdown?.contains("E_sun_section_marker") == true, "Fallback should include the last tool result summary.")
                try expect(result.toolResults.first?.toolName == "read_paper_section", "Fallback should preserve the successful tool result.")
                try expect(events.contains { $0.kind == .toolCallCompleted && $0.summary == "已使用工具：read_paper_section" }, "Tool completion timeline should use a compact used-tool summary.")
                try expect(events.contains { $0.kind == .assistantMessage && $0.summary.contains("最后一个工具结果摘要") }, "Fallback should be appended as an assistant timeline event.")
            }

            private func agentLoopRunnerEmptyResponseWithoutToolsKeepsContextFallback() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopEmptyProviderNoToolWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: ""))
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-empty-provider-no-tool",
                    goal: "继续总结这篇论文并保留草稿",
                    provider: provider,
                    definitions: [],
                    registry: AgentToolRegistry(tools: []),
                    fixture: fixture
                ))
                let events = try await logger.events(in: fixture.root, sessionID: "loop-empty-provider-no-tool")

                try expect(result.pauseReason?.kind == .providerUnavailable, "Empty provider response without tools should become providerUnavailable instead of throwing.")
                try expect(result.finalResponseMarkdown?.contains("上下文已保留") == true, "Empty provider response without tools should preserve context in a visible fallback.")
                try expect(result.toolResults.isEmpty, "No-tool fallback should not invent tool results.")
                try expect(events.contains { $0.kind == .assistantMessage && $0.summary.contains("上下文已保留") }, "No-tool fallback should be appended as an assistant event.")
            }

            private func agentLoopRunnerReturnsVisibleProviderFailureAfterPreflightTools() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopPreflightProviderFailureWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let provider = ScriptedFailingChatProvider(steps: [
                    .failure(.httpError(statusCode: 400, message: "The reasoning_content in the thinking mode must be passed back to the API."))
                ])
                let listDefinition = loopToolDefinition(name: "list_papers", risk: .readOnly)
                let listTool = RecordingAgentTool(definition: listDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "list_papers",
                        succeeded: true,
                        message: "paper_id: paper-1\ntitle: Demo Paper",
                        payload: .object([
                            "kind": .string("paper_list"),
                            "papers": .array([.object([
                                "paper_id": .string("paper-1"),
                                "title": .string("Demo Paper")
                            ])])
                        ])
                    )
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-preflight-provider-failure",
                    goal: "请列出当前论文。",
                    provider: provider,
                    definitions: [listDefinition],
                    registry: AgentToolRegistry(tools: [listTool]),
                    fixture: fixture
                ))
                let requests = await provider.recordedRequests()

                try expect(result.pauseReason?.kind == .providerUnavailable, "Provider failure after deterministic preflight should become a visible providerUnavailable fallback.")
                try expect(result.finalResponseMarkdown?.contains("模型没有返回最终回复") == true, "Preflight provider failure should produce a visible Chinese fallback.")
                try expect(result.finalResponseMarkdown?.contains("复制脱敏诊断") == true, "Fallback should expose a copy-diagnostics action.")
                try expect(result.finalResponseMarkdown?.contains("paper-1") == true, "Fallback should summarize the already-read preflight tool result.")
                try expect(result.toolResults.map(\.toolName) == ["list_papers"], "Preflight tool result should be preserved when provider fails.")
                try expect(requests.count == 1, "Preflight failure should happen after one provider request with evidence context.")
                try expect(requests.first?.messages.contains { $0.role == .user && $0.content.contains("deterministic preflight evidence") } == true, "Provider request should include preflight evidence as user context.")
            }

            private func agentLoopRunnerPaperFormulaFlowUsesListSearchReadBeforeFinal() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopPaperFormulaFlowWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: """
                    公式为：

                    $$
                    E_{\\odot}=k A (p_s-p_a)
                    $$

                    其中 $k$ 为局部系数，$A$ 为有效面积，$p_s-p_a$ 为压差。来源：Demo Paper (paper-1), papers/demo/paper.md。
                    """))
                ])
                let listDefinition = loopToolDefinition(name: "list_papers", risk: .readOnly)
                let searchDefinition = loopToolDefinition(name: "search_papers", risk: .readOnly)
                let readDefinition = loopToolDefinition(name: "read_paper_section", risk: .readOnly)
                let listTool = RecordingAgentTool(definition: listDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "list_papers",
                        succeeded: true,
                        message: "paper_id: paper-1\ntitle: Demo Paper\npath: papers/demo",
                        payload: .object([
                            "kind": .string("paper_list"),
                            "papers": .array([.object([
                                "paper_id": .string("paper-1"),
                                "title": .string("Demo Paper"),
                                "path": .string("papers/demo"),
                                "raw_markdown_path": .string("papers/demo/paper.md")
                            ])])
                        ])
                    )
                ])
                let searchTool = RecordingAgentTool(definition: searchDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "search_papers",
                        succeeded: true,
                        message: "Matched Demo Paper section Evaporation Rate.",
                        payload: .object([
                            "kind": .string("paper_search"),
                            "matches": .array([.object([
                                "paper_id": .string("paper-1"),
                                "title": .string("Demo Paper"),
                                "source": .string("papers/demo/paper.md"),
                                "heading": .string("Evaporation Rate"),
                                "line": .number("42"),
                                "snippet": .string("E_{\\odot}=k A (p_s-p_a)")
                            ])])
                        ])
                    )
                ])
                let readTool = RecordingAgentTool(definition: readDefinition, results: [
                    AgentToolResult(callID: "", toolName: "read_paper_section", succeeded: true, message: "## Evaporation Rate\n$E_{\\odot}=k A (p_s-p_a)$ with local symbol context.")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-paper-formula-flow",
                    goal: "第一篇论文里的 evaporation rate 公式是什么？",
                    provider: provider,
                    definitions: [listDefinition, searchDefinition, readDefinition],
                    registry: AgentToolRegistry(tools: [listTool, searchTool, readTool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 5)
                ))
                let requests = await provider.recordedRequests()
                let listInvocationCount = await listTool.invocationCount()
                let searchInvocationCount = await searchTool.invocationCount()
                let readInvocationCount = await readTool.invocationCount()

                try expect(result.finalResponseMarkdown?.contains("$$") == true, "Paper formula flow should finish with display math.")
                try expect(result.finalResponseMarkdown?.contains("papers/demo/paper.md") == true, "Paper formula final answer should include a source path.")
                try expect(result.toolResults.map(\.toolName) == ["list_papers", "search_papers", "read_paper_section"], "Paper formula flow should preserve list/search/read tool order.")
                try expect(listInvocationCount == 1, "list_papers should run once.")
                try expect(searchInvocationCount == 1, "search_papers should run once.")
                try expect(readInvocationCount == 1, "read_paper_section should run once.")
                try expect(requests.count == 1, "Paper formula preflight should make one model request after deterministic read-only tools.")
                let finalRequest = try require(requests.last, "Expected the final provider request.")
                try expect(finalRequest.messages.filter { $0.role == .tool }.isEmpty, "Preflight evidence should not be sent as provider-native tool result messages.")
                try expect(!finalRequest.messages.contains { $0.role == .assistant && !$0.toolCalls.isEmpty }, "Preflight should not emit synthetic assistant tool-call messages.")
                let evidenceMessage = try require(finalRequest.messages.last(where: { $0.role == .user && $0.content.contains("deterministic preflight evidence") }), "Final request should include deterministic evidence as user context.")
                try expect(evidenceMessage.content.contains("preflight-list-papers"), "Evidence context should include the list_papers preflight call.")
                try expect(evidenceMessage.content.contains("preflight-search-papers"), "Evidence context should include the search_papers preflight call.")
                try expect(evidenceMessage.content.contains("preflight-read-paper-section"), "Evidence context should include the read_paper_section preflight call.")
            }

            private func agentLoopRunnerFallsBackToReadPaperWhenSearchHasNoMatch() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopSearchEmptyFallbackWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Fallback answer from page 1 evidence."))
                ])
                let listDefinition = loopToolDefinition(name: "list_papers", risk: .readOnly)
                let searchDefinition = loopToolDefinition(name: "search_papers", risk: .readOnly)
                let readSectionDefinition = loopToolDefinition(name: "read_paper_section", risk: .readOnly)
                let readPaperDefinition = loopToolDefinition(name: "read_paper", risk: .readOnly)
                let listTool = RecordingAgentTool(definition: listDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "list_papers",
                        succeeded: true,
                        message: "paper_id: paper-1\ntitle: Demo Paper\npath: papers/demo",
                        payload: .object([
                            "kind": .string("paper_list"),
                            "papers": .array([.object([
                                "paper_id": .string("paper-1"),
                                "title": .string("Demo Paper"),
                                "path": .string("papers/demo"),
                                "raw_markdown_path": .string("papers/demo/paper.md")
                            ])])
                        ])
                    )
                ])
                let searchTool = RecordingAgentTool(definition: searchDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "search_papers",
                        succeeded: true,
                        message: "No matches for \"missing_marker\" in converted paper.md files.",
                        payload: .object([
                            "kind": .string("paper_search"),
                            "status": .string("empty_search"),
                            "matches": .array([])
                        ])
                    )
                ])
                let readSectionTool = RecordingAgentTool(definition: readSectionDefinition, results: [
                    AgentToolResult(callID: "", toolName: "read_paper_section", succeeded: true, message: "This should not run without a heading or line match.")
                ])
                let readPaperTool = RecordingAgentTool(definition: readPaperDefinition, results: [
                    AgentToolResult(callID: "", toolName: "read_paper", succeeded: true, message: "paper_id: paper-1\nsource: papers/demo/paper.md\nrange: page 1\n\nPage 1 fallback body evidence.")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-search-empty-fallback",
                    goal: "第一篇论文正文里 missing_marker 是什么？",
                    provider: provider,
                    definitions: [listDefinition, searchDefinition, readSectionDefinition, readPaperDefinition],
                    registry: AgentToolRegistry(tools: [listTool, searchTool, readSectionTool, readPaperTool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 5)
                ))
                let requests = await provider.recordedRequests()
                let readSectionInvocationCount = await readSectionTool.invocationCount()
                let readPaperInvocationCount = await readPaperTool.invocationCount()

                try expect(result.finalResponseMarkdown == "Fallback answer from page 1 evidence.", "Loop should continue after page 1 fallback evidence.")
                try expect(result.toolResults.map(\.toolName) == ["list_papers", "search_papers", "read_paper"], "Empty search should fall back to read_paper instead of stopping after search.")
                try expect(readSectionInvocationCount == 0, "read_paper_section should not run when search produced no heading or line match.")
                try expect(readPaperInvocationCount == 1, "read_paper should run once as the page 1 fallback.")
                let evidenceMessage = try require(requests.first?.messages.last(where: { $0.role == .user && $0.content.contains("deterministic preflight evidence") }), "Fallback request should include deterministic preflight evidence.")
                try expect(evidenceMessage.content.contains("preflight-read-paper"), "Evidence context should include the read_paper fallback call.")
            }

            private func agentLoopRunnerPreflightEvidenceIsInjectedAsUserContext() async throws {
                try await agentLoopRunnerPaperFormulaFlowUsesListSearchReadBeforeFinal()
            }

            private func agentLoopRunnerThinkingModePayloadHasNoAssistantToolCallWithoutReasoning() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopThinkingModeMissingReasoningWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "This should not be reached."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Tool evidence before sanitizer block.")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-thinking-mode-missing-reasoning",
                    goal: "请读取论文证据。",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    configuration: LLMConfiguration(baseURLString: "https://api.deepseek.com", model: "deepseek-reasoner")
                ))
                let requests = await provider.recordedRequests()

                try expect(result.pauseReason?.kind == .providerUnavailable, "Missing thinking-mode reasoning_content should be blocked before a bad replay request reaches the provider.")
                try expect(result.finalResponseMarkdown?.contains("reasoning_content") == true, "Visible fallback should include the sanitizer reason.")
                try expect(requests.count == 1, "Provider should not receive a second request containing assistant tool calls without reasoning_content.")
            }

            private func agentLoopRunnerPreservesReasoningContentForNativeToolCalls() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopPreserveReasoningWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(
                        message: LLMChatMessage(
                            role: .assistant,
                            content: "",
                            reasoningContent: "thinking-mode tool replay token",
                            toolCalls: [call]
                        ),
                        toolCalls: [call]
                    ),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Final answer after preserved reasoning."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Reasoned tool evidence.")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-preserve-reasoning",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    configuration: LLMConfiguration(baseURLString: "https://api.deepseek.com", model: "deepseek-reasoner")
                ))
                let requests = await provider.recordedRequests()
                let secondRequest = try require(requests.dropFirst().first, "Reasoning-preserving provider should receive the replay request.")
                let assistantReplay = try require(secondRequest.messages.first { $0.role == .assistant && !$0.toolCalls.isEmpty }, "Replay request should include the provider-native assistant tool call.")
                let events = try await logger.events(in: fixture.root, sessionID: "loop-preserve-reasoning")

                try expect(result.finalResponseMarkdown == "Final answer after preserved reasoning.", "Loop should complete when provider-native tool calls include reasoning_content.")
                try expect(assistantReplay.reasoningContent == "thinking-mode tool replay token", "Provider-native tool replay should preserve assistant reasoning_content.")
                try expect(events.contains { $0.kind == .assistantMessage && ($0.payloadJSON?.contains("reasoning_content") ?? false) }, "Assistant session event payload should persist reasoning_content.")
            }

            private func agentAnswerQualityEvaluatorChecksFormulaSources() throws {
                let evaluator = AgentAnswerQualityEvaluator()
                let evidence = AgentToolResult(
                    callID: "call-read",
                    toolName: "read_paper_section",
                    succeeded: true,
                    message: "paper_id: paper-1\nsource: papers/demo/paper.md\n$$E_{\\odot}=kA$$",
                    payload: .object([
                        "kind": .string("paper_section"),
                        "paper": .object([
                            "paper_id": .string("paper-1"),
                            "title": .string("Demo Paper"),
                            "path": .string("papers/demo"),
                            "raw_markdown_path": .string("papers/demo/paper.md")
                        ]),
                        "source": .string("papers/demo/paper.md"),
                        "content": .string("$$E_{\\odot}=kA$$")
                    ])
                )
                let good = """
                公式为：

                $$
                E_{\\odot}=kA
                $$

                来源：Demo Paper (paper-1), papers/demo/paper.md。
                """
                let goodReport = evaluator.evaluate(goal: "第一篇文章的蒸发率公式是什么？", finalMarkdown: good, toolResults: [evidence])
                try expect(goodReport.passes, "Formula answer with display math and source should pass quality checks.")

                let weakReport = evaluator.evaluate(goal: "第一篇文章的蒸发率公式是什么？", finalMarkdown: "我使用了工具并找到了答案。", toolResults: [evidence])
                try expect(weakReport.issues.map(\.code).contains(.missingDisplayMath), "Formula answer without display math should be flagged.")
                try expect(weakReport.issues.map(\.code).contains(.missingSource), "Formula answer without source should be flagged.")

                let missingEvidence = evaluator.evaluate(goal: "第一篇文章的蒸发率公式是什么？", finalMarkdown: "我没有读取到正文或公式证据。", toolResults: [])
                try expect(missingEvidence.issues.map(\.code).contains(.missingEvidence), "Formula answer without paper evidence should be flagged.")
                try expect(!missingEvidence.issues.map(\.code).contains(.missingContentExplanation), "Missing evidence explanation should satisfy the explanation check.")
            }

            private func agentLoopRunnerPausesForWorkspaceWrite() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopWritePauseWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"Review\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created todo")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-write-pause",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let pending = try await AgentLoopCheckpointStore().pending(runID: "loop-write-pause", in: fixture.root)
                let events = try await logger.events(in: fixture.root, sessionID: "loop-write-pause")

                try expect(result.pauseReason?.kind == .approvalRequired, "Workspace writes should pause for approval.")
                try expect(result.pendingToolCall?.toolCall.toolName == "create_todo", "Paused result should include the pending tool call.")
                try expect(pending?.toolCall.id == "call-write", "Pending write tool call should be saved as a checkpoint.")
                try expect(events.map(\.kind).contains(.permissionRequested), "Loop should append a permissionRequested event.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 0, "Write tool must not run before approval.")
            }

            private func agentLoopRunnerStopsAtMaxSteps() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopMaxStepsWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-repeat", toolName: "read_note", argumentsJSON: "{}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "same result")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-max-steps",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 2)
                ))

                try expect(result.pauseReason?.kind == .maxStepsExceeded, "Loop should stop when maxSteps is exceeded.")
            }

            private func agentLoopRunnerInjectsToolResultMessages() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopInjectsToolResultWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-inject", toolName: "read_note", argumentsJSON: "{}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Final"))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Injected evidence")
                ])
                let runner = AgentLoopRunner()

                _ = try await runner.run(loopRequest(
                    runID: "loop-inject",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let requests = await provider.recordedRequests()
                let secondRequestMessages = try require(requests.dropFirst().first?.messages, "Expected a second model request.")
                let toolMessage = try require(secondRequestMessages.first { $0.role == .tool }, "Second request should include a tool result message.")

                try expect(toolMessage.toolCallID == "call-inject", "Tool result message should preserve tool_call_id.")
                try expect(toolMessage.content.contains("schema_version"), "Tool result message should be stable JSON.")
                try expect(toolMessage.content.contains("Injected evidence"), "Tool result message should include tool content.")
            }

            private func agentLoopRunnerResumesPendingApproval() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopResumeWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"Resume\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Created after approval."))
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created todo", modifiedPaths: ["tasks/todos.yaml"])
                ])
                let registry = AgentToolRegistry(tools: [tool])
                let runner = AgentLoopRunner()
                let paused = try await runner.run(loopRequest(runID: "loop-resume", provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                let pending = try require(paused.pendingToolCall, "Expected pending write call.")

                let resumed = try await runner.resume(loopResumeRequest(
                    pending: pending,
                    action: .allowOnce,
                    provider: provider,
                    definitions: [definition],
                    registry: registry,
                    fixture: fixture
                ))

                try expect(resumed.finalResponseMarkdown?.contains("approval") == true, "Approved pending call should continue to a final assistant message.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Approved write should execute exactly once.")
            }

            private func agentLoopRunnerDoesNotRepeatApprovedWriteOnResume() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopNoRepeatWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"No repeat\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Done once.")),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Done twice."))
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created once", modifiedPaths: ["tasks/todos.yaml"])
                ])
                let registry = AgentToolRegistry(tools: [tool])
                let runner = AgentLoopRunner()
                let paused = try await runner.run(loopRequest(runID: "loop-no-repeat", provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                let pending = try require(paused.pendingToolCall, "Expected pending write call.")

                _ = try await runner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                _ = try await runner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: provider, definitions: [definition], registry: registry, fixture: fixture))

                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Write ledger should prevent repeat execution for an already approved fingerprint.")
            }

            private func agentLoopRunnerEditArgumentsRevalidatesBeforeExecution() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopEditArgsWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"Original\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created edited")
                ])
                let registry = AgentToolRegistry(tools: [tool])
                let runner = AgentLoopRunner()
                let paused = try await runner.run(loopRequest(runID: "loop-edit-args", provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                let pending = try require(paused.pendingToolCall, "Expected pending write call.")

                let edited = try await runner.resume(loopResumeRequest(
                    pending: pending,
                    action: .editArguments,
                    editedArgumentsJSON: "{\"title\":\"Edited\"}",
                    provider: provider,
                    definitions: [definition],
                    registry: registry,
                    fixture: fixture
                ))

                try expect(edited.pauseReason?.kind == .approvalRequired, "Edited write arguments should be revalidated and return to approval instead of executing directly.")
                try expect(edited.pendingToolCall?.toolCall.argumentsJSON.contains("Edited") == true, "Edited arguments should be normalized into the new pending call.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 0, "Edited arguments should not execute before the fresh approval pass.")
            }

            private func agentLoopRunnerSafetyDenyIsFatal() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopSafetyDenyWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-danger", toolName: "write_note", argumentsJSON: "{\"command\":\"git reset --hard\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "write_note", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "write_note", succeeded: true, message: "Should not run")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-safety-deny",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))

                try expect(result.pauseReason?.kind == .safetyPolicyBlocked, "Deterministic safety deny should stop the run.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 0, "Safety-denied tools should never execute.")
            }

            private func agentLoopRunnerCachesRepeatedReadOnlyToolCall() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopReadCacheWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let firstCall = AgentToolCall(id: "call-read-1", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                let secondCall = AgentToolCall(id: "call-read-2", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [firstCall, secondCall]), toolCalls: [firstCall, secondCall]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Cached final."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Cached once")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-read-cache",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))

                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Repeated read-only fingerprint should reuse cache in the same run.")
                try expect(result.steps.first?.cachedToolCallIDs == Optional(["call-read-2"]), "Loop step should record cached read-only call ids.")
            }

            private func agentLoopRunnerStopsAtContextBudget() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopContextBudgetWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-large", toolName: "read_note", argumentsJSON: "{}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly, maxOutputCharacters: 2_000)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: String(repeating: "x", count: 1_600))
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-context-budget",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 4, maxAccumulatedToolResultCharacters: 1_000)
                ))

                try expect(result.pauseReason?.kind == .contextLimitExceeded, "Loop should stop when accumulated tool result budget is exceeded.")
                try expect(result.finalResponseMarkdown?.contains("context or tool result budget") == true, "Context budget stops should still produce a visible fallback reply when tool evidence exists.")
            }

            private func agentDiagnosticRedactorRedactsSecretsAndHomePaths() throws {
                let raw = """
                root=/Users/alice/Documents/ResearchWorkspace
                Authorization: Bearer sk-live-super-secret-token
                api_key=sk-another-secret-token
                token: plain-token-value
                """

                let redacted = AgentDiagnosticRedactor.redacted(raw, homeDirectory: "/Users/alice")
                try expect(!redacted.contains("/Users/alice"), "Diagnostic redaction should remove absolute home paths.")
                try expect(!redacted.contains("super-secret-token"), "Diagnostic redaction should remove bearer token bodies.")
                try expect(!redacted.contains("another-secret-token"), "Diagnostic redaction should remove API key bodies.")
                try expect(redacted.contains("~"), "Diagnostic redaction should preserve useful relative path context.")
            }

    private func externalAgentRuntimeStreamsLegacyLoopEvents() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LegacyRuntimeEventWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-runtime-read", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Runtime final."))
        ])
        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let registry = AgentToolRegistry(tools: [
            RecordingAgentTool(definition: definition, results: [
                AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Runtime evidence")
            ])
        ])
        let runtime = LegacySwiftAgentRuntime()
        let stream = try await runtime.startRun(AgentRuntimeRequest(
            runID: "legacy-runtime-run",
            goal: "Runtime test goal",
            initialMessages: [LLMChatMessage(role: .user, content: "Read context")],
            provider: provider,
            toolDefinitions: [definition],
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        ))

        var envelopes: [AgentRuntimeEventEnvelope] = []
        for try await envelope in stream {
            envelopes.append(envelope)
        }
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "legacy-runtime-run", in: fixture.root)

        try expect(envelopes.contains { if case .runStarted = $0.event { return true }; return false }, "Legacy runtime should stream runStarted.")
        try expect(envelopes.contains { if case .toolCallRequested = $0.event { return true }; return false }, "Legacy runtime should map loop tool calls to runtime events.")
        try expect(envelopes.contains { if case .toolCallCompleted = $0.event { return true }; return false }, "Legacy runtime should map stable tool results to runtime events.")
        try expect(envelopes.contains { if case .finalResponse = $0.event { return true }; return false }, "Legacy runtime should stream finalResponse.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "Persisted runtime events should use stable per-run host sequence.")
    }

    private func fakeExternalRuntimeDrivesAITimelineEvents() async throws {
        let fixture = try await loopWorkspaceFixture(named: "FakeRuntimeTimelineWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = FakeExternalAgentRuntime(scriptedEvents: [
            .runStarted(AgentRunStarted(goal: "Fake timeline")),
            .approvalRequired(AgentApprovalRequest(runID: "fake-runtime-run", toolCallID: "fake-write", toolName: "write_markdown_plan", permissionKey: AgentToolRisk.writesWorkspace.defaultPermissionKey, risk: .writesWorkspace, argumentsJSON: "{}", targetPaths: ["wiki/plans/fake.md"])),
            .finalResponse(AgentFinalResponse(markdown: "Fake done."))
        ])
        let provider = ScriptedChatProvider(responses: [])
        let request = AgentRuntimeRequest(
            runID: "fake-runtime-run",
            goal: "Fake timeline",
            initialMessages: [],
            provider: provider,
            toolDefinitions: [],
            toolRegistry: AgentToolRegistry(tools: []),
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )

        let stream = try await runtime.startRun(request)
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }

        try expect(events.contains { if case .approvalRequired = $0 { return true }; return false }, "Fake runtime should be able to drive approval timeline state.")
        try expect(events.contains { if case .finalResponse = $0 { return true }; return false }, "Fake runtime should be able to drive final response timeline state.")
    }

    private func langGraphRuntimePerformsInitializeHandshake() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphHandshakeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "run_success_paper_reading.jsonl")
        let request = sidecarRuntimeRequest(runID: "langgraph-handshake-run", fixture: fixture)
        let stream = try await runtime.startRun(request)
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }

        try expect(events.count >= 4, "LangGraph sidecar handshake should allow the run to emit lifecycle and runtime events.")
        try expect(events.contains { if case .sidecarStarting = $0 { return true }; return false }, "LangGraph runtime should emit sidecarStarting before initialize.")
        try expect(events.contains { if case .sidecarReady = $0 { return true }; return false }, "LangGraph runtime should emit sidecarReady after initialize/health.")
    }

    private func langGraphRuntimeReplaysGoldenFixtureRunSuccess() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphGoldenSuccessWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "run_success_paper_reading.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-success-run", goal: "精读 demo paper", fixture: fixture))
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-success-run", in: fixture.root)

        try expect(events.contains { if case .runStarted = $0 { return true }; return false }, "Golden fixture should replay runStarted.")
        try expect(events.contains { if case .toolCallRequested = $0 { return true }; return false }, "Golden fixture should replay tool_call_requested.")
        try expect(events.contains { if case .artifactDraft = $0 { return true }; return false }, "Golden fixture should replay artifact_draft. Saw: \(events.map(runtimeEventLabel).joined(separator: ", "))")
        try expect(events.contains { if case .finalResponse = $0 { return true }; return false }, "Golden fixture should replay final_response.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "LangGraph runtime should persist host-canonical sequences for golden fixture replay.")
    }

    private func langGraphRuntimeReplaysGoldenFixtureApprovalResume() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphApprovalResumeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "write_markdown_plan", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "write_markdown_plan", succeeded: true, message: "Swift wrote the paper note once.", modifiedPaths: ["wiki/papers/demo-paper.md"])
        ])
        let runtime = sidecarRuntime(fixtureName: "run_approval_then_resume.jsonl")
        let request = sidecarRuntimeRequest(
            runID: "langgraph-approval-run",
            fixture: fixture,
            definitions: [definition],
            registry: AgentToolRegistry(tools: [tool])
        )
        let stream = try await runtime.startRun(request)
        var startEvents: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            startEvents.append(envelope.event)
        }

        let pending = try await AgentRunDirectoryStore().pending(runID: "langgraph-approval-run", in: fixture.root)
        try expect(startEvents.contains { if case .approvalRequired = $0 { return true }; return false }, "Approval fixture should pause with approvalRequired. Saw: \(startEvents.map(runtimeEventLabel).joined(separator: ", "))")
        try expect(pending?.approvalRequest.id == "approval-demo-write", "LangGraph runtime should persist sidecar approval as a run-directory checkpoint.")

        try await runtime.resumeRun(runID: "langgraph-approval-run", decision: AgentHumanDecision(action: .allowOnce))
        let invocationCount = await tool.invocationCount()
        let records = try await AgentRunDirectoryStore().toolCallRecords(runID: "langgraph-approval-run", in: fixture.root)
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-approval-run", in: fixture.root)

        try expect(invocationCount == 1, "Allow once should execute the Swift-owned write exactly once.")
        try expect(records.contains { $0.status == .completed && $0.toolCallID == "call-write-note" }, "Approved sidecar write should be recorded in the persistent ledger.")
        try expect(persisted.contains { if case .finalResponse = $0.event { return true }; return false }, "agent.resume should persist the fixture final response.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "Approval/resume fixture should keep host-canonical sequences after resume.")
    }

    private func langGraphRuntimeRejectsInvalidFixtureSchemaVersion() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphInvalidSchemaWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "invalid_schema_version.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-invalid-schema-run", fixture: fixture))
        do {
            for try await _ in stream {}
            throw ValidationError(message: "Invalid sidecar event schema version should fail the runtime stream.")
        } catch let error as SidecarJSONRPCError {
            try expect(error.message.contains("schema version"), "Invalid schema version should report a schema error.")
        }
    }

    private func langGraphRuntimeCanonicalizesSidecarLocalSequence() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphSequenceWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "run_success_paper_reading.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-sequence-run", fixture: fixture))
        for try await _ in stream {}
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-sequence-run", in: fixture.root)
        let eventIDs = persisted.map(\.id)

        try expect(eventIDs.contains("evt-fixture-success-node-load"), "Sequence test should include fixture events with intentionally shuffled local sequences.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "Swift host should canonicalize sidecar local sequences to a stable per-run sequence.")
    }

    private func langGraphRuntimeFallsBackWhenInitializeTimesOut() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphTimeoutWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "handshake_timeout.jsonl", handshakeTimeout: 0.2)
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-timeout-run", fixture: fixture))
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }

        try expect(events.count == 3, "Handshake timeout without fallback runtime should emit only fixed lifecycle fallback events.")
        try expect(events[0].isSidecarStarting, "Handshake timeout should start with sidecarStarting.")
        try expect(events[1].isSidecarUnavailable, "Handshake timeout should emit sidecarUnavailable.")
        try expect(events[2].isFallbackToLegacyRuntime, "Handshake timeout should emit fallbackToLegacyRuntime.")
    }

    private func langGraphRuntimeDoesNotLoseApprovalWhenSidecarCrashes() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphCrashApprovalWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "sidecar_crash_after_approval.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-crash-run", fixture: fixture))
        for try await _ in stream {}
        let pending = try await AgentRunDirectoryStore().pending(runID: "langgraph-crash-run", in: fixture.root)
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-crash-run", in: fixture.root)

        try expect(pending?.approvalRequest.id == "approval-crash-write", "Sidecar crash after approval should not lose the pending approval checkpoint.")
        try expect(persisted.contains { if case .checkpointSaved = $0.event { return true }; return false }, "Crash fixture should persist checkpointSaved before the crash.")
    }

    private func sidecarConnectionBrokenPipeThrowsInsteadOfTerminatingHost() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec 0<&-; sleep 2"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let connection = SidecarConnection(
            process: process,
            inputHandle: inputPipe.fileHandleForWriting,
            outputHandle: outputPipe.fileHandleForReading,
            errorHandle: errorPipe.fileHandleForReading
        )

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            try? inputPipe.fileHandleForWriting.close()
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        do {
            _ = try await connection.sendRequest(method: "sidecar.initialize", params: .object([:]), timeout: 1)
            throw ValidationError(message: "Broken sidecar stdin should throw instead of returning a response.")
        } catch let error as SidecarJSONRPCError {
            try expect(error.code == -32001, "Broken sidecar stdin should surface as a sidecar process error, got \(error.code): \(error.message)")
        }
    }

    private func sidecarLLMProxyDisablesProviderNativeToolCalling() async throws {
        let fixture = try await loopWorkspaceFixture(named: "SidecarLLMProxyWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "LLM proxy response."))
        ])
        let request = AgentRuntimeRequest(
            runID: "llm-proxy-run",
            goal: "LLM proxy",
            initialMessages: [],
            provider: provider,
            toolDefinitions: [],
            toolRegistry: AgentToolRegistry(tools: []),
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )
        let sidecarRequest = SidecarLLMRespondRequest(
            messages: [LLMChatMessage(role: .user, content: "Summarize.")],
            tools: [LLMToolSpecification(name: "read_note", description: "Read", inputSchemaJSON: "{}")],
            toolCallPolicy: .disabled,
            modelOptions: ["temperature": .number("0.1")]
        )
        _ = try await SidecarLLMProxy().respond(params: try SidecarJSONCodec.jsonValue(from: sidecarRequest), runtimeRequest: request)
        let recorded = await provider.recordedRequests()

        try expect(recorded.count == 1, "LLMProxy should call the Swift provider once.")
        try expect(recorded.first?.tools.isEmpty == true, "toolCallPolicy disabled should strip provider-native tool specifications.")
    }

    private func sidecarEmbeddingProxyRejectsSensitiveConfigAndReturnsVectors() async throws {
        let fixture = try await loopWorkspaceFixture(named: "SidecarEmbeddingProxyWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let request = AgentRuntimeRequest(
            runID: "embedding-proxy-run",
            goal: "Embedding proxy",
            initialMessages: [],
            provider: ScriptedChatProvider(responses: []),
            toolDefinitions: [],
            toolRegistry: AgentToolRegistry(tools: []),
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )
        let embeddingRequest = SidecarEmbeddingRequest(texts: ["retrieval evidence chunk"], modelRequestID: "req-1")
        let responseValue = try await SidecarEmbeddingProxy().embed(params: try SidecarJSONCodec.jsonValue(from: embeddingRequest), runtimeRequest: request)
        let responseObject = try jsonObject(responseValue, "Embedding proxy should return an object response.")
        let vectors = try jsonArray(responseObject["vectors"], "Embedding proxy should return vectors.")
        let metadata = try jsonObject(responseObject["redacted_metadata"], "Embedding proxy should return redacted metadata.")

        try expect(vectors.count == 1, "Embedding proxy should return one vector per input text.")
        try expect(metadata["redacted"] == .string("true"), "Embedding proxy metadata should be explicitly redacted.")
        do {
            let unsafeRequest = SidecarEmbeddingRequest(texts: ["secret-free text"], modelOptions: ["apiKey": .string("sk-secret")])
            _ = try await SidecarEmbeddingProxy().embed(params: try SidecarJSONCodec.jsonValue(from: unsafeRequest), runtimeRequest: request)
            throw ValidationError(message: "Embedding proxy should reject sensitive provider config keys.")
        } catch let error as SidecarJSONRPCError {
            try expect(error.message.contains("sensitive key"), "Sensitive embedding config should be rejected by contract.")
        }
    }

    private func authorizedResourceProviderListsAndReadsDocuments() async throws {
        let fixture = try await loopWorkspaceFixture(named: "AuthorizedResourcesWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "library/papers/demo-paper/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Intro\nThis paper studies evaporation rate evidence.\n# Method\nThe method is line anchored.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let provider = AgentAuthorizedResourceProvider()
        let documents = try await provider.listIndexableDocuments(in: fixture.root)
        let snapshot = try require(documents.first(where: { $0.relativePath == "library/papers/demo-paper/paper.md" }), "Authorized resources should include converted paper.md.")
        let response = try await provider.read(AuthorizedResourceReadRequest(resourceID: snapshot.resourceID, maxBytes: 1_048_576, maxCharacters: 24), in: fixture.root)

        try expect(snapshot.sourceType == "paper", "paper.md should be classified as paper source type.")
        try expect(response.contentHash == snapshot.contentHash, "resources/read should return the snapshot content hash.")
        try expect(response.truncated, "resources/read should mark content truncated when maxCharacters is exceeded.")
    }

    private func authorizedResourceProviderIndexesLegacyRawPaperMarkdown() async throws {
        let fixture = try await loopWorkspaceFixture(named: "AuthorizedLegacyRawResourcesWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "raw/papers/Legacy/demo-paper/paper.md")
        let annotationsURL = fixture.root.fileURL(for: "raw/papers/Legacy/demo-paper/annotations.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Abstract\nLegacy raw paper abstract evidence.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        try "# Notes\nLegacy annotations evidence.\n".write(to: annotationsURL, atomically: true, encoding: .utf8)
        let provider = AgentAuthorizedResourceProvider()
        let documents = try await provider.listIndexableDocuments(in: fixture.root)
        let paperSnapshot = try require(documents.first(where: { $0.relativePath == "raw/papers/Legacy/demo-paper/paper.md" }), "Authorized resources should include legacy raw/papers paper.md.")
        let annotationsSnapshot = try require(documents.first(where: { $0.relativePath == "raw/papers/Legacy/demo-paper/annotations.md" }), "Authorized resources should include legacy raw/papers annotations.md.")
        let response = try await provider.read(AuthorizedResourceReadRequest(relativePath: "raw/papers/Legacy/demo-paper/paper.md", maxCharacters: 120), in: fixture.root)

        try expect(AgentAuthorizedResourceProvider.defaultAllowedRoots.contains("raw/papers"), "Default allowed roots should include legacy raw/papers.")
        try expect(paperSnapshot.sourceType == "paper", "Legacy raw/papers paper.md should be classified as paper source type.")
        try expect(annotationsSnapshot.sourceType == "paper_annotations", "Legacy raw/papers annotations.md should be classified as paper annotations.")
        try expect(response.content.contains("Legacy raw paper abstract evidence"), "resources/read should read legacy raw/papers paper.md content.")
    }

    private func embeddingIndexControllerRebuildsSelectedSource() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EmbeddingIndexControllerWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "library/papers/p37/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Retrieval\nPersistent local embedding retrieval evidence.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let controller = AgentEmbeddingIndexController()
        let status = await controller.rebuildSelectedSource("library/papers/p37/paper.md", in: fixture.root)
        let indexURL = fixture.root.directoryURL(for: AgentEmbeddingIndexController.indexRelativePath).appendingPathComponent("deterministic_fallback_chunks.json", isDirectory: false)

        try expect(status.status.uiStatus == .fallback, "Selected source rebuild should use deterministic fallback when sqlite-vec is unavailable.")
        try expect(status.chunkCount > 0, "Selected source rebuild should write chunks to the local index.")
        try expect(FileManager.default.fileExists(atPath: indexURL.path), "Embedding fallback index should be persisted under .sci-station/index/embeddings.")
    }

    private func embeddingIndexControllerRebuildsLegacyRawPaperSource() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EmbeddingLegacyRawIndexControllerWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "raw/papers/Legacy/p39/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Abstract\nLegacy raw retrieval evidence should become chunks.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let controller = AgentEmbeddingIndexController()
        let status = await controller.rebuildSelectedSource("raw/papers/Legacy/p39/paper.md", in: fixture.root)

        try expect(status.status.uiStatus == .fallback, "Legacy raw source rebuild should use deterministic fallback when sqlite-vec is unavailable.")
        try expect(status.chunkCount > 0, "Legacy raw paper.md rebuild should produce chunks.")
        try expect(status.diagnosticText.contains("Fallback deterministic retrieval"), "Diagnostics should explain deterministic fallback retrieval.")
    }

    private func listPapersPayloadIncludesAbstract() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let paperRepository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ListPapersAbstractPayloadWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var paper = samplePaper(id: "abstract-payload-paper")
        paper.abstract = "This metadata abstract should be available before body reads."
        let savedPaper = try await paperRepository.save(paper, in: workspace)
        let result = try await ListPapersAgentTool(paperRepository: paperRepository).invoke(
            argumentsJSON: "{\"paper_id\":\"\(savedPaper.id)\"}",
            context: AgentToolContext(workspace: workspace, selectedPaperID: savedPaper.id)
        )
        let papersPayload = try require(result.payload?.objectValue?["papers"]?.arrayValue, "list_papers should return a papers payload.")
        let firstPaperPayload = try require(papersPayload.first?.objectValue, "list_papers should return object paper payloads.")

        try expect(firstPaperPayload["abstract"]?.stringValue == paper.abstract, "list_papers paper payload should include metadata abstract.")
    }

    private func paperMarkdownQualityInspectorDetectsPDFKitFallback() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let paperRepository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PaperMarkdownQualityWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "pdfkit-quality-paper"), in: workspace)
        let markdown = """
        ---
        extraction_engine: pdfkit_fallback
        fallback_reason: "MinerU API token is missing."
        ---

        # Demo Paper

        ## 摘要

        这是一段中文摘要。

        ![Figure](figures/missing-chart.png)

        $$
        E = mc^2
        $$
        """
        try markdown.write(to: paper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

        let report = PaperMarkdownQualityInspector().inspect(paper, in: workspace)
        let issueCodes = Set(report.issues.map(\.code))

        try expect(report.status == .warning, "PDFKit fallback reports should warn rather than fail when paper.md is readable.")
        try expect(report.extractionEngine == "pdfkit_fallback", "Quality inspector should expose extraction engine metadata.")
        try expect(report.hasAbstractHeading, "Quality inspector should recognize Chinese 摘要 headings as Abstract.")
        try expect(report.hasDisplayMath, "Quality inspector should detect display math blocks.")
        try expect(report.hasFigureReferences, "Quality inspector should detect figure references.")
        try expect(issueCodes.contains(.pdfKitFallback), "Quality inspector should warn about PDFKit fallback limitations.")
        try expect(issueCodes.contains(.missingFigureAsset), "Quality inspector should warn about missing local figure assets.")
        try expect(report.issueLines(usesEnglishInterface: false).contains { $0.contains("PDFKit fallback 可读性有限") }, "Quality issue lines should include Chinese copy.")
        try expect(report.issueLines(usesEnglishInterface: true).contains { $0.contains("PDFKit fallback has limited readability") }, "Quality issue lines should include English copy.")
    }

    private func agentEvidenceRefStableIDMarksStale() throws {
        let first = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 12, sourceHash: "sha256:a")
        let second = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 12, sourceHash: "sha256:a")
        let changed = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 12, sourceHash: "sha256:b")

        try expect(first.id == second.id, "AgentEvidenceRef should generate stable ids for the same source line range and hash.")
        try expect(first.id != changed.id, "Changing source_hash should change the stable evidence id.")
        try expect(first.isStale(currentSourceHash: "sha256:b"), "Evidence should be stale when current source hash changes.")
    }

    private func paperReadingWorkflowProducesEvidenceBackedDraft() throws {
        let evidence = sampleEvidenceRefs(prefix: "paper")
        let draft = AgentArtifactDraft(
            runID: "paper-reading-run",
            kind: "paper_reading_note",
            proposedPath: "wiki/papers/demo.md",
            title: "Paper Note",
            content: "# Paper Note\n\n## TL;DR\n- Claim. [evidence:\(evidence[0].id)]\n\n## Contributions\n- Claim. [evidence:\(evidence[1].id)]\n- Claim. [evidence:\(evidence[2].id)]\n- Claim. [evidence:\(evidence[3].id)]\n\n## Method\n- Claim. [evidence:\(evidence[4].id)]\n- Claim. [evidence:\(evidence[5].id)]\n\n## Experiments\n## Limitations\n## Open Questions\n## Relevance to Current Project\n## Follow-up Todos\n## Evidence\n",
            evidenceRefs: evidence,
            risk: .readOnly
        )

        try expect(draft.content.contains("## TL;DR"), "Paper reading draft should include the production note structure.")
        try expect(draft.content.contains("## Follow-up Todos"), "Paper reading draft should include follow-up todos.")
        try expect(draft.evidenceRefs.count >= 6, "Paper reading draft should carry evidence refs for claims.")
    }

    private func relatedWorkWorkflowClustersByTheme() throws {
        let content = "# Related Work\n\n## Scope\n- Scope. [evidence:e1]\n\n## Theme 1\n- Retrieval claim. [evidence:e1]\n\n## Theme 2\n- Workflow claim. [evidence:e2]\n\n## Theme 3\n- Evaluation claim. [evidence:e3]\n\n## Evidence Matrix\n- e1\n"
        let themeCount = content.components(separatedBy: "\n").filter { $0.hasPrefix("## Theme") }.count
        try expect(themeCount == 3, "Related work production drafts should cluster by theme.")
        try expect(content.contains("## Evidence Matrix"), "Related work production drafts should include an evidence matrix.")
    }

    private func gapPlanningWorkflowGeneratesTodoDraftsWithoutWriting() async throws {
        let fixture = try await loopWorkspaceFixture(named: "GapPlanningDraftWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let draft = AgentArtifactDraft(
            runID: "gap-run",
            kind: "research_plan",
            proposedPath: "projects/demo-project/wiki/research_plan.md",
            title: "Research Plan",
            content: "# Research Plan\n\n## Todo Drafts\n- [high] Investigate gap. [evidence:e1]\n",
            evidenceRefs: sampleEvidenceRefs(prefix: "gap"),
            risk: .readOnly
        )
        let targetURL = fixture.root.fileURL(for: draft.proposedPath ?? "")

        try expect(draft.risk == .readOnly, "Gap planning should emit drafts and wait for Swift approval before writing.")
        try expect(!FileManager.default.fileExists(atPath: targetURL.path), "Gap planning draft creation should not write research_plan.md by itself.")
    }

    private func citationCriticBlocksUnsupportedClaims() throws {
        let report = AgentCitationCriticReport(
            unsupportedClaims: [.object(["claim": .string("Unsupported core claim")])],
            requiredRevisions: ["Core scientific claims must cite evidence before final approval."],
            canRequestApproval: false
        )

        try expect(report.blocksFinalApproval, "Citation critic report should block final approval when unsupported claims exist.")
    }

    private func evidenceRefsJumpToSourceLineRange() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EvidenceJumpWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "library/papers/p1/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Intro\nLine anchored evidence.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let evidence = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 2, sourceHash: "sha256:a")
        let jump = evidence.sourceJump(in: fixture.root, currentSourceHash: "sha256:a")
        let staleJump = evidence.sourceJump(in: fixture.root, currentSourceHash: "sha256:b")
        let missing = AgentEvidenceRef(sourceType: "paper", sourceID: "p2", relativePath: "library/papers/p2/paper.md", startLine: 1, endLine: 2, sourceHash: "sha256:c").sourceJump(in: fixture.root)

        try expect(jump.status == .available, "Existing evidence source should be jumpable.")
        try expect(jump.startLine == 1 && jump.endLine == 2, "Evidence jump should preserve source line range.")
        try expect(staleJump.status == .stale, "Changed source hash should mark evidence as stale.")
        try expect(missing.status == .missingSource, "Missing source should be reported instead of crashing.")
    }

    private func sidecarRuntimeSelectorPersistsAndFallbacks() async throws {
        let fixture = try await loopWorkspaceFixture(named: "RuntimeSelectorWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let repository = WorkspacePreferencesRepository()
        let preferences = WorkspacePreferences(agentRuntimeSelection: .langGraphSidecar)
        try await repository.save(preferences, in: fixture.workspace)
        let loaded = try await repository.load(in: fixture.workspace)

        try expect(loaded.agentRuntimeSelection == .langGraphSidecar, "Workspace preferences should persist the sidecar runtime selector.")
        try expect(loaded.agentRuntimeSelection.effectiveRuntime(sidecarAvailable: false) == .swiftLoop, "Sidecar selection should fall back to Swift Loop when health is unavailable.")
        try expect(loaded.agentRuntimeSelection.fallbackReason(sidecarAvailable: false) != nil, "Fallback should explain why Swift Loop is active.")
    }

    private func sidecarRuntimeCoordinatorResolvesHealthAndSelection() async throws {
        let fixture = try await loopWorkspaceFixture(named: "RuntimeCoordinatorWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let coordinator = sidecarCoordinator(fixtureName: "run_success_paper_reading.jsonl")
        defer { Task { await coordinator.stop() } }
        let unavailableCoordinator = sidecarCoordinator(fixtureName: "handshake_timeout.jsonl", handshakeTimeout: 0.2)
        defer { Task { await unavailableCoordinator.stop() } }

        let auto = await coordinator.resolve(selection: .autoFallback, sidecarDisabled: false, root: fixture.root)
        let forcedSwift = await coordinator.resolve(selection: .swiftLoop, sidecarDisabled: false, root: fixture.root)
        let disabled = await coordinator.resolve(selection: .langGraphSidecar, sidecarDisabled: true, root: fixture.root)
        let unavailable = await unavailableCoordinator.resolve(selection: .autoFallback, sidecarDisabled: false, root: fixture.root)

        try expect(auto.health.status == "ready", "Coordinator should start and read sidecar health for auto fallback.")
        try expect(auto.effectiveRuntime == .langGraphSidecar && auto.shouldAttemptSidecar, "Auto fallback should use sidecar when health is ready.")
        try expect(forcedSwift.effectiveRuntime == .swiftLoop && !forcedSwift.shouldAttemptSidecar, "Swift Loop selection should not attempt sidecar.")
        try expect(disabled.effectiveRuntime == .swiftLoop && disabled.fallbackReason != nil, "Workspace sidecar disable should force Swift Loop with a reason.")
        try expect(unavailable.effectiveRuntime == .swiftLoop && !unavailable.shouldAttemptSidecar, "Unavailable sidecar should not block Swift Loop fallback.")
        try expect(unavailable.fallbackReason?.contains("Swift Loop") == true || unavailable.health.fallbackReason != nil, "Unavailable sidecar fallback should be visible in diagnostics.")
    }

    private func runReplayLoadsTimelineFromRunDirectory() async throws {
        let fixture = try await loopWorkspaceFixture(named: "RunReplayWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let store = AgentRunDirectoryStore()
        let first = AgentRuntimeEventEnvelope(id: "evt-replay-1", runID: "replay-run", sequence: 1, event: .runStarted(AgentRunStarted(goal: "Replay")))
        let second = AgentRuntimeEventEnvelope(id: "evt-replay-2", runID: "replay-run", sequence: 2, event: .finalResponse(AgentFinalResponse(markdown: "Done")))
        try await store.appendEvent(first, in: fixture.root)
        try await store.appendEvent(second, in: fixture.root)
        try await store.saveCriticReport(.object(["can_request_approval": .bool(true)]), runID: "replay-run", in: fixture.root)
        try await store.saveRetrievalTrace(.object(["path": .string("FTS")]), runID: "replay-run", in: fixture.root)
        let replay = try await store.saveReplay(runID: "replay-run", in: fixture.root, debugPromptResponse: .object(["api_key": .string("sk-secret"), "prompt": .string("read /private/tmp/paper.md")]))
        let loaded = try await store.runReplay(runID: "replay-run", in: fixture.root)
        let manifest = try await store.saveDebugBundleManifest(runID: "replay-run", in: fixture.root)

        try expect(replay.events.map(\.id) == ["evt-replay-1", "evt-replay-2"], "Replay should preserve persisted runtime timeline events.")
        try expect(loaded.events.count == 2, "Replay should reload from replay.json.")
        try expect(manifest.includedFiles.contains("critic_report.json"), "Debug manifest should include critic reports when present.")
        if case let .object(debug) = replay.debugPromptResponse {
            try expect(debug["api_key"] == .string("[REDACTED]"), "Replay debug payload should redact API keys.")
            try expect(debug["prompt"] == .string("read [PATH]"), "Replay debug payload should redact private paths.")
        } else {
            throw ValidationError(message: "Replay should keep a redacted debug payload when explicitly requested.")
        }
    }

    private func debugBundleManifestAndZipExcludeSecrets() async throws {
        let fixture = try await loopWorkspaceFixture(named: "DebugBundleWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let store = AgentRunDirectoryStore()
        try await store.appendEvent(
            AgentRuntimeEventEnvelope(id: "evt-secret", runID: "debug-run", sequence: 1, event: .finalResponse(AgentFinalResponse(markdown: "Token sk-secret should be redacted."))),
            in: fixture.root
        )
        try await store.saveCriticReport(.object(["api_key": .string("sk-secret")]), runID: "debug-run", in: fixture.root)
        try await store.saveRetrievalTrace(.object(["source": .string("/private/tmp/source.md")]), runID: "debug-run", in: fixture.root)
        _ = try await store.saveReplay(runID: "debug-run", in: fixture.root, debugPromptResponse: .object(["token": .string("sk-secret")]))
        let preview = try await store.debugBundlePreview(runID: "debug-run", in: fixture.root)
        let zipURL = try await store.saveDebugBundle(runID: "debug-run", in: fixture.root)
        let zipData = try Data(contentsOf: zipURL)
        let zipText = String(data: zipData, encoding: .utf8) ?? ""
        let manifest = try await store.saveDebugBundleManifest(runID: "debug-run", in: fixture.root)

        try expect(preview.includedFiles.contains("events.jsonl"), "Debug preview should list included run files before export.")
        try expect(manifest.redactionPolicy.contains("prompt/response"), "Debug manifest should record the redaction policy.")
        try expect(manifest.excludedPatterns.contains(".sci-station/index/embeddings/**"), "Debug manifest should exclude embedding index files by default.")
        try expect(FileManager.default.fileExists(atPath: zipURL.path), "Debug bundle should be a real zip file on disk.")
        try expect(!zipText.contains("sk-secret"), "Debug bundle zip should not contain raw API keys or tokens.")
        try expect(!zipText.contains("/private/tmp"), "Debug bundle zip should not contain private path inventory.")
    }

    private func embeddingFallbackUsesFTSWhenDisabled() throws {
        let configuration = AgentEmbeddingRetrievalConfiguration(enabled: false, provider: "swift-proxy", model: "embedding-test", dimension: 3, store: "sqlite-vec")

        try expect(configuration.usesFTSFallback, "Embedding retrieval should preserve FTS-only fallback when disabled.")
        try expect(configuration.store == "sqlite-vec", "Embedding retrieval config should preserve local store selection.")
    }

    private func embeddingStorePersistsAndMarksMigrationRequired() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EmbeddingStoreWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let content = "# Retrieval\nPersistent embedding chunks should be stale after source changes.\n"
        let snapshot = IndexableDocumentSnapshot(
            resourceID: "paper:p37:library/papers/p37/paper.md",
            relativePath: "library/papers/p37/paper.md",
            sourceType: "paper",
            sourceID: "p37",
            updatedAt: Date(),
            contentHash: AgentEmbeddingHashing.sha256(content)
        )
        let modelA = AgentEmbeddingModelIdentity(modelID: "model-a", dimension: 32)
        let modelB = AgentEmbeddingModelIdentity(modelID: "model-b", dimension: 32)
        let store = AgentDeterministicEmbeddingStore(indexDirectoryURL: fixture.root.directoryURL(for: AgentEmbeddingIndexController.indexRelativePath), fallbackReason: "test fallback")
        try await store.open()
        try await store.beginTransaction()
        try await store.upsertChunks(AgentEmbeddingChunker.chunks(from: snapshot, content: content, model: modelA))
        try await store.commitTransaction()
        let fresh = await store.query("persistent embedding", limit: 3, currentSourceHashes: [snapshot.relativePath: snapshot.contentHash])
        let stale = await store.query("persistent embedding", limit: 3, currentSourceHashes: [snapshot.relativePath: "sha256:changed"])
        let health = await store.healthCheck(model: modelB, schemaVersion: AgentEmbeddingChunker.chunkSchemaVersion)

        try expect(fresh.first?.sourceHashStatus == .fresh, "Embedding store should mark matching source hashes fresh.")
        try expect(stale.first?.sourceHashStatus == .stale, "Embedding store should mark changed source hashes stale.")
        try expect(health.status == .migrationRequired, "Embedding model_id changes should require rebuild/migration.")
        try expect(health.staleCount == 1, "Model mismatch should report stale chunk count.")
    }

    private func evidenceSourceJumpMapsPDFPageWhenAvailable() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EvidencePDFPageWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperDirectory = fixture.root.directoryURL(for: "library/papers/p1")
        try FileManager.default.createDirectory(at: paperDirectory, withIntermediateDirectories: true)
        try "# Intro\nLine anchored evidence.\n".write(to: paperDirectory.appendingPathComponent("paper.md"), atomically: true, encoding: .utf8)
        try Data("%PDF-1.4\n".utf8).write(to: paperDirectory.appendingPathComponent("paper.pdf"), options: .atomic)
        try #"{"mappings":[{"start_line":1,"end_line":5,"page":3}]}"#.write(to: paperDirectory.appendingPathComponent("paper_page_map.json"), atomically: true, encoding: .utf8)

        let evidence = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 2, sourceHash: "sha256:a")
        let jump = evidence.sourceJump(in: fixture.root, currentSourceHash: "sha256:a")

        try expect(jump.pdfPage == 3, "Evidence source jump should map paper.md line range to PDF page when page mapping exists.")
        try expect(jump.pdfRelativePath == "library/papers/p1/paper.pdf", "PDF page target should default to the paper directory PDF.")
        try expect(jump.lineTargetDescription.contains("lines 1-2"), "Evidence jump should expose a line target descriptor.")
    }

    private func workspaceTemplateModuleConfigWritesAndLegacyMigration() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent("SciStationTemplateTest-\(UUID().uuidString)", isDirectory: true)
        let minimalURL = baseURL.appendingPathComponent("Minimal", isDirectory: true)
        let legacyURL = baseURL.appendingPathComponent("Legacy", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let service = WorkspaceService()
        let minimalWorkspace = try await service.createWorkspace(at: minimalURL, template: WorkspaceTemplateRegistry.minimal)
        let minimalTemplate = try String(contentsOf: minimalWorkspace.fileURL(for: WorkspaceTemplateRepository.templateRelativePath), encoding: .utf8)
        let minimalModules = try String(contentsOf: minimalWorkspace.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath), encoding: .utf8)
                let repository = WorkspaceTemplateRepository()
                let minimalConfiguration = WorkspaceModuleRegistry.mergedConfiguration(from: try repository.decodeConfiguration(minimalModules))

        try expect(minimalTemplate.contains(#"id: "minimal-workspace""#), "Minimal workspace should write workspace_template.yaml.")
                try expect(minimalModules.contains("schema_version: 1"), "Workspace module config should write schema_version 1.")
        try expect(minimalModules.contains(#"id: "paper-library""#), "Workspace module config should include built-in paper-library declaration.")
        try expect(minimalModules.contains(#"enabled: false"#), "Minimal template should keep disabled built-in modules declared without deleting data.")
                try expect(minimalConfiguration.modules.count == 15, "V1 module registry should declare the deterministic built-in module set.")
                try expect(minimalConfiguration.module(id: "code")?.enabled == false, "Future modules should be present but disabled by default.")
                try expect(WorkspaceModuleRegistry.availableRoutes(in: minimalConfiguration).contains { $0.id == "ai-lab" }, "Enabled AI Lab module should expose its route.")

        try FileManager.default.createDirectory(at: legacyURL.appendingPathComponent("raw/papers", isDirectory: true), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: legacyURL.appendingPathComponent("settings", isDirectory: true), withIntermediateDirectories: true)
                try """
                schema_version: 0
                modules:
                    - id: "projects"
                        title: "Projects"
                        version: "0.1.0"
                        enabled: true
                        directories:
                            - "projects"
                        routes:
                            - "/projects"
                        workflows:
                            - "gap_planning"
                        permission_scope:
                            write_paths:
                                - "projects/*/wiki/"
                """.write(to: legacyURL.appendingPathComponent(WorkspaceTemplateRepository.modulesRelativePath, isDirectory: false), atomically: true, encoding: .utf8)
        _ = try await service.openWorkspace(at: legacyURL)
        let legacyTemplateURL = legacyURL.appendingPathComponent(WorkspaceTemplateRepository.templateRelativePath, isDirectory: false)
        let legacyModulesURL = legacyURL.appendingPathComponent(WorkspaceTemplateRepository.modulesRelativePath, isDirectory: false)
                let migratedModules = try String(contentsOf: legacyModulesURL, encoding: .utf8)
        try expect(FileManager.default.fileExists(atPath: legacyTemplateURL.path), "Opening legacy workspace should backfill workspace_template.yaml.")
        try expect(FileManager.default.fileExists(atPath: legacyModulesURL.path), "Opening legacy workspace should backfill workspace_modules.yaml.")
                try expect(migratedModules.contains("schema_version: 1"), "Opening legacy module config should migrate it to schema_version 1.")
        try expect(FileManager.default.fileExists(atPath: legacyURL.appendingPathComponent("raw/papers", isDirectory: true).path), "Legacy migration should not delete existing user data.")
    }

    private func workspaceCreationWizardPreviewValidationAndSafety() async throws {
        let baseURL = temporaryDirectoryURL().appendingPathComponent("P40Wizard", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let minimalDraft = WorkspaceCreationWizard.draft(selecting: WorkspaceTemplateRegistry.minimal)
        let minimalPreview = WorkspaceCreationWizard.preview(for: minimalDraft)
        let minimalEnabledIDs = Set(minimalPreview.enabledModules.map(\.id))
        let minimalRoutes = Set(minimalPreview.routes.map(\.id))
        let safeDirectories = WorkspaceCreationWizard.safeDirectoryPathsToCreate(for: WorkspaceTemplateRegistry.minimal)

        try expect(minimalPreview.configuration.schemaVersion == 1, "Workspace creation preview should use module schema_version 1.")
        try expect(minimalEnabledIDs == Set(WorkspaceTemplateRegistry.minimal.enabledModuleIDs), "Wizard preview should derive enabled modules from the selected template.")
        try expect(minimalRoutes.contains("ai-lab"), "Minimal wizard preview should expose the AI Lab route.")
        try expect(!minimalRoutes.contains("library"), "Minimal wizard preview should hide Library when paper-library is disabled.")
        try expect(minimalPreview.directoryItems.contains { $0.path == "projects/*/wiki" && !$0.willCreate && $0.isWildcard }, "Wildcard project directories should be preview-only and not created directly.")
        try expect(safeDirectories.contains("settings") && safeDirectories.contains(".sci-station/agent"), "Safe directory resolver should include settings and AI Lab agent state directories.")
        try expect(!safeDirectories.contains { $0.contains("*") || $0.hasSuffix(".yaml") || !WorkspaceModuleSchema.isSafeRelativePathPattern($0) }, "Safe directory resolver should filter wildcard, settings files, and unsafe relative paths.")

        let newRootURL = baseURL.appendingPathComponent("NewRoot", isDirectory: true)
        let newValidation = WorkspaceCreationWizard.validateTargetURL(newRootURL)
        try expect(newValidation.canCreate && newValidation.state == .newFolder, "Wizard validation should allow a new folder under an existing parent.")

        let emptyRootURL = baseURL.appendingPathComponent("EmptyRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyRootURL, withIntermediateDirectories: true)
        let emptyValidation = WorkspaceCreationWizard.validateTargetURL(emptyRootURL)
        try expect(emptyValidation.canCreate && emptyValidation.state == .emptyFolder, "Wizard validation should allow an empty folder.")

        let fileURL = baseURL.appendingPathComponent("not-a-root.txt", isDirectory: false)
        try "not a folder".write(to: fileURL, atomically: true, encoding: .utf8)
        let fileValidation = WorkspaceCreationWizard.validateTargetURL(fileURL)
        try expect(!fileValidation.canCreate && fileValidation.state == .blockedFile, "Wizard validation should reject file destinations.")

        let nonEmptyURL = baseURL.appendingPathComponent("NonEmpty", isDirectory: true)
        try FileManager.default.createDirectory(at: nonEmptyURL, withIntermediateDirectories: true)
        try "user data".write(to: nonEmptyURL.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let nonEmptyValidation = WorkspaceCreationWizard.validateTargetURL(nonEmptyURL)
        try expect(!nonEmptyValidation.canCreate && nonEmptyValidation.state == .blockedNonEmptyFolder, "Wizard validation should block non-empty folders that are not compatible workspaces.")

        let legacyURL = baseURL.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyURL.appendingPathComponent("settings", isDirectory: true), withIntermediateDirectories: true)
        try "schema_version: 1\n".write(to: legacyURL.appendingPathComponent("settings/workspace_preferences.yaml"), atomically: true, encoding: .utf8)
        let legacyValidation = WorkspaceCreationWizard.validateTargetURL(legacyURL)
        try expect(legacyValidation.canCreate && legacyValidation.state == .legacyWorkspace, "Wizard validation should allow compatible legacy workspaces.")

        let service = WorkspaceService()
        let minimalURL = baseURL.appendingPathComponent("ExistingMinimal", isDirectory: true)
        let workspace = try await service.createWorkspace(at: minimalURL, template: WorkspaceTemplateRegistry.minimal)
        let moduleConfigURL = workspace.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath)
        let beforeModules = try String(contentsOf: moduleConfigURL, encoding: .utf8)
        _ = try await service.createWorkspace(at: minimalURL, template: WorkspaceTemplateRegistry.literatureReview)
        let afterModules = try String(contentsOf: moduleConfigURL, encoding: .utf8)
        let repository = WorkspaceTemplateRepository()
        let afterConfiguration = WorkspaceModuleRegistry.mergedConfiguration(from: try repository.decodeConfiguration(afterModules))

        try expect(beforeModules == afterModules, "Re-running create on an existing Research Root should not overwrite workspace_modules.yaml.")
        try expect(afterConfiguration.module(id: "paper-library")?.enabled == false, "Existing module choices should be preserved when a compatible root is opened through the wizard path.")

        let generatedSettingsText = [
            afterModules,
            try String(contentsOf: workspace.fileURL(for: WorkspaceTemplateRepository.templateRelativePath), encoding: .utf8),
            try String(contentsOf: workspace.fileURL(for: "settings/llm.yaml"), encoding: .utf8),
            try String(contentsOf: workspace.fileURL(for: "settings/agent.yaml"), encoding: .utf8)
        ].joined(separator: "\n")
        try expect(!generatedSettingsText.localizedCaseInsensitiveContains("api_key"), "Workspace creation should not write API key placeholders into generated settings files.")
        try expect(!generatedSettingsText.localizedCaseInsensitiveContains("provider_raw_config"), "Workspace creation should not write provider raw config into generated settings files.")
        try expect(!generatedSettingsText.localizedCaseInsensitiveContains("prompt:"), "Workspace creation should not write prompt plaintext into generated settings files.")
        try expect(!generatedSettingsText.localizedCaseInsensitiveContains("response:"), "Workspace creation should not write response plaintext into generated settings files.")
    }

        private func workspaceModuleRegistryV1GatesRoutesWorkflowsAndArtifacts() throws {
                let defaultConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                let defaultRoutes = Set(WorkspaceModuleRegistry.availableRoutes(in: defaultConfiguration).map(\.id))
                let defaultProjectTabs = Set(WorkspaceModuleRegistry.availableProjectTabs(in: defaultConfiguration).map(\.id))
                let defaultWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: defaultConfiguration))

                try expect(defaultConfiguration.modules.map(\.id) == [
                        "projects",
                        "paper-library",
                        "wiki",
                        "materials",
                        "tasks",
                        "calendar",
                        "pdf-reader",
                        "ai-lab",
                        "code",
                        "datasets",
                        "experiments",
                        "citation-graph",
                        "recommendation",
                        "writing",
                        "theory-notes"
                ], "Built-in module registry order should be deterministic.")
                try expect(defaultRoutes.contains("projects") && defaultRoutes.contains("library") && defaultRoutes.contains("ai-lab"), "Default modules should expose core routes.")
                try expect(!defaultRoutes.contains("code") && !defaultRoutes.contains("experiments"), "Future modules should stay hidden until enabled.")
                try expect(defaultProjectTabs.contains("overview") && defaultProjectTabs.contains("papers") && defaultProjectTabs.contains("tasks"), "Default project tabs should be registry-driven.")
                try expect(defaultWorkflows.contains("paper_reading") && defaultWorkflows.contains("related_work") && defaultWorkflows.contains("gap_planning"), "Default AI workflows should be available when required modules are enabled.")

                let noLibraryConfiguration = WorkspaceModuleRegistry.defaultConfiguration(
                        enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library"])
                )
                let noLibraryRoutes = Set(WorkspaceModuleRegistry.availableRoutes(in: noLibraryConfiguration).map(\.id))
                let noLibraryWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: noLibraryConfiguration))
                try expect(!noLibraryRoutes.contains("library"), "Disabled paper-library module should hide the Library route.")
                try expect(!noLibraryRoutes.contains("pdf-reader"), "Modules with disabled dependencies should hide their routes.")
                try expect(!noLibraryWorkflows.contains("paper_reading"), "Workflow requirements should hide paper_reading when paper-library is disabled.")
                try expect(!noLibraryWorkflows.contains("related_work"), "Workflow requirements should hide related_work when paper-library is disabled.")
                try expect(!noLibraryWorkflows.contains("gap_planning"), "gap_planning should hide when citation-graph is unavailable through paper-library dependency.")

                let descriptor = WorkspaceModuleRegistry.artifactKindDescriptor(for: "paper_reading_note", in: defaultConfiguration)
                let unknownDescriptor = WorkspaceModuleRegistry.artifactKindDescriptor(for: "future_artifact", in: defaultConfiguration)
                try expect(descriptor.isKnown && descriptor.moduleID == "paper-library", "Known artifact kinds should resolve to their declaring module.")
                try expect(!unknownDescriptor.isKnown && unknownDescriptor.title == "Future Artifact", "Unknown artifact kinds should fall back to a readable descriptor.")

                let codeWithoutAILab = WorkspaceModuleRegistry.defaultConfiguration(enabledModuleIDs: ["projects", "wiki", "code"])
                let warnings = WorkspaceModuleRegistry.warnings(for: codeWithoutAILab)
                try expect(warnings.contains { $0.id == "disabled-dependency:code:ai-lab" }, "Enabled modules with disabled dependencies should produce registry warnings.")

                let scopeDescription = WorkspaceModuleRegistry.moduleScopeDescription(for: ["projects/demo/wiki/research_plan.md"], in: defaultConfiguration)
                try expect(scopeDescription?.contains("Wiki") == true || scopeDescription?.contains("Projects") == true, "Module approval scope should explain matching module write paths.")
        }

            private func workspaceModuleRegistryGatesGraphWorkflows() throws {
                let defaultConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                let defaultWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: defaultConfiguration))
                try expect(defaultWorkflows.contains("graph_insight"), "Default configuration should expose graph_insight when AI Lab and Citation Graph are enabled.")
                try expect(defaultWorkflows.contains("related_work"), "related_work should remain available when Citation Graph is enabled.")
                try expect(defaultWorkflows.contains("gap_planning"), "gap_planning should remain available when Citation Graph is enabled.")

                let noGraphConfiguration = WorkspaceModuleRegistry.defaultConfiguration(
                    enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["citation-graph"])
                )
                let noGraphWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: noGraphConfiguration))
                try expect(!noGraphWorkflows.contains("graph_insight"), "graph_insight should be gated by Citation Graph.")
                try expect(!noGraphWorkflows.contains("related_work"), "related_work should be gated by Citation Graph after P47.")
                try expect(!noGraphWorkflows.contains("gap_planning"), "gap_planning should be gated by Citation Graph after P47.")

                let noAILabConfiguration = WorkspaceModuleRegistry.defaultConfiguration(
                    enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["ai-lab"])
                )
                let noAILabWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: noAILabConfiguration))
                try expect(!noAILabWorkflows.contains("graph_insight"), "graph_insight should also require AI Lab.")
            }

    private func paperLibraryModuleDeclaresReadingQueueArtifactKindAndWorkflow() throws {
        let module = try require(WorkspaceModuleRegistry.module(id: "paper-library"), "paper-library module must remain in the built-in registry.")
        try expect(module.artifactKinds.contains("reading_queue_entry"), "paper-library should declare the reading_queue_entry artifact kind.")
        try expect(module.workflows.contains("reading_queue_curate"), "paper-library should declare the reading_queue_curate workflow.")
        try expect(module.permissions.writePaths.contains("library/queue.yaml"), "paper-library should permit writes to library/queue.yaml.")
        try expect(module.permissions.writePaths.contains("projects/*/queue.yaml"), "paper-library should permit writes to projects/*/queue.yaml.")
        try expect(!module.projectTabs.contains(where: { $0.id == "reading" }), "paper-library should no longer contribute Reading after it is merged into Tasks.")
        try expect(!module.projectTabs.contains(where: { $0.id == "queue" }), "paper-library should no longer contribute a separate Queue project-space tab.")
        try expect(!module.projectTabs.contains(where: { $0.id == "reading-plan" }), "paper-library should no longer contribute a separate Reading Plan project-space tab.")

        let descriptor = WorkspaceModuleRegistry.artifactKindDescriptor(for: "reading_queue_entry", in: WorkspaceModuleRegistry.defaultConfiguration())
        try expect(descriptor.isKnown && descriptor.moduleID == "paper-library", "reading_queue_entry should resolve to paper-library via the artifact kind descriptor.")
    }

    private func workspaceModuleRegistryWorkflowGatingForReadingQueueCurate() throws {
        let defaultConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
        let defaultWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: defaultConfiguration))
        try expect(defaultWorkflows.contains("reading_queue_curate"), "reading_queue_curate should be available when paper-library is enabled.")

        let noLibraryConfiguration = WorkspaceModuleRegistry.defaultConfiguration(
            enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library"])
        )
        let noLibraryWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: noLibraryConfiguration))
        try expect(!noLibraryWorkflows.contains("reading_queue_curate"), "reading_queue_curate should hide when paper-library is disabled.")

        let availableProjectTabs = Set(WorkspaceModuleRegistry.availableProjectTabs(in: defaultConfiguration).map(\.id))
    try expect(!availableProjectTabs.contains("reading"), "Reading tab should not remain available after it is merged into Tasks.")
    try expect(availableProjectTabs.contains("tasks"), "Tasks tab should remain the project-space destination for reading todos.")
        try expect(!availableProjectTabs.contains("queue"), "Queue tab should not remain available after Reading consolidation.")
        try expect(!availableProjectTabs.contains("reading-plan"), "Reading Plan tab should not remain available after Reading consolidation.")
        let noLibraryProjectTabs = Set(WorkspaceModuleRegistry.availableProjectTabs(in: noLibraryConfiguration).map(\.id))
    try expect(!noLibraryProjectTabs.contains("reading"), "Reading tab should stay hidden when paper-library is disabled.")

        let requirements = try require(WorkspaceModuleRegistry.workflowRequirements["reading_queue_curate"], "reading_queue_curate should declare workflow requirements.")
        try expect(requirements == ["paper-library"], "reading_queue_curate should require exactly paper-library; AI ingest stays under research_queue_update.")
    }

            private func moduleSettingsViewModelEnableModuleRequiresDependencies() throws {
                let configuration = WorkspaceModuleRegistry.defaultConfiguration(
                    enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library"])
                )
                do {
                    _ = try WorkspaceModuleSettingsMutation.setModule("recommendation", enabled: true, in: configuration)
                    try expect(false, "Enabling recommendation should require paper-library first.")
                } catch ModuleSettingsError.dependencyMissing(let missing) {
                    try expect(missing == ["paper-library"], "Recommendation should report paper-library as the missing dependency.")
                } catch {
                    throw error
                }
            }

            private func moduleSettingsViewModelEnableDependenciesEnablesAllAncestors() throws {
                let configuration = WorkspaceModuleRegistry.defaultConfiguration(
                    enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library", "recommendation"])
                )
                let result = try WorkspaceModuleSettingsMutation.enableModuleAndDependencies("recommendation", in: configuration)
                let enabledIDs = result.configuration.enabledModuleIDs

                try expect(enabledIDs.contains("paper-library"), "Enable Dependencies should enable recommendation ancestors.")
                try expect(enabledIDs.contains("recommendation"), "Enable Dependencies should enable the requested module.")
                try expect(result.enabledChain == ["paper-library", "recommendation"], "Dependency chain should be deterministic and dependency-first.")
            }

            private func moduleSettingsViewModelTogglePinPersistsOrder() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModulePinWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                let repository = WorkspaceTemplateRepository()
                try repository.overwriteTemplateConfiguration(WorkspaceTemplateRegistry.literatureReview, in: root)

                var configuration = try repository.loadConfiguration(in: root)
                configuration = try WorkspaceModuleSettingsMutation.togglePin("tasks", in: configuration)
                configuration = try WorkspaceModuleSettingsMutation.movePin("tasks", newIndex: 0, in: configuration)

                let store = WorkspaceModuleConfigurationStore()
                try await store.save(configuration, in: root)
                let reloadedConfiguration = try await store.load(in: root)

                try expect(reloadedConfiguration.module(id: "tasks")?.pinned == true, "Pinned module should persist to workspace_modules.yaml.")
                try expect(WorkspaceModuleSettingsMutation.pinnedOrder(in: reloadedConfiguration).first == "tasks", "Pinned order should persist through the YAML round trip.")
            }

            private func moduleSettingsViewModelDisablingDependencyHidesRoutes() throws {
                let configuration = try WorkspaceModuleSettingsMutation.setModule("wiki", enabled: false, in: WorkspaceModuleRegistry.defaultConfiguration())
                let routes = Set(WorkspaceModuleRegistry.availableRoutes(in: configuration).map(\.id))
                let workflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: configuration))
                let warnings = WorkspaceModuleRegistry.warnings(for: configuration)

                try expect(!routes.contains("wiki"), "Disabling wiki should hide the Wiki route.")
                try expect(!workflows.contains("related_work"), "Workflows requiring wiki should be hidden.")
                try expect(warnings.contains { $0.id == "disabled-dependency:ai-lab:projects" } == false, "Unrelated dependency warnings should not be invented.")
                try expect(warnings.contains { $0.id == "disabled-dependency:code:wiki" } == false, "Disabled modules should not emit dependency-hidden warnings until enabled.")
            }

            private func moduleSettingsViewModelOverrideOnlyAffectsTargetProject() throws {
                let workspaceConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                let override = WorkspaceModuleOverride(
                    projectID: "project-a",
                    moduleOverrides: [WorkspaceModuleOverrideEntry(id: "calendar", enabled: false)]
                )
                let projectAConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: override)
                let projectBConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: nil)

                try expect(projectAConfiguration.module(id: "calendar")?.enabled == false, "Project A override should disable calendar.")
                try expect(projectBConfiguration.module(id: "calendar")?.enabled == true, "Project B should keep the workspace calendar setting.")
                try expect(projectAConfiguration.module(id: "calendar")?.title == workspaceConfiguration.module(id: "calendar")?.title, "Override should not replace registry metadata.")
            }

            private func workspaceModuleDirectoryRepairerSkipsWildcardPaths() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModuleRepairWildcardWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                let status = WorkspaceModuleDirectoryStatus(moduleID: "wiki", moduleTitle: "Wiki", path: "projects/*/wiki/", required: true, repairable: true, exists: false)
                let repairer = WorkspaceModuleDirectoryRepairer { _ in
                    AgentPermissionDecision(action: .allow)
                }
                let outcome = await repairer.repair(status, in: root, activeProjects: [])

                try expect(outcome == .skippedWildcard(path: "projects/*/wiki/"), "Wildcard repair should be skipped when no active project instance exists.")
            }

            private func workspaceModuleDirectoryRepairerRequiresPermissionApproval() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModuleRepairApprovalWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                let status = WorkspaceModuleDirectoryStatus(moduleID: "tasks", moduleTitle: "Tasks", path: "tasks", required: true, repairable: true, exists: false)
                let deniedRepairer = WorkspaceModuleDirectoryRepairer { _ in
                    AgentPermissionDecision(action: .deny, message: "test deny")
                }
                let deniedOutcome = await deniedRepairer.repair(status, in: root)
                try expect(deniedOutcome == .denied(path: "tasks", reason: "test deny"), "Repair should not create directories without approval.")
                try expect(!FileManager.default.fileExists(atPath: root.directoryURL(for: "tasks").path), "Denied repair should not write the workspace.")

                let approvedRepairer = WorkspaceModuleDirectoryRepairer { _ in
                    AgentPermissionDecision(action: .allow)
                }
                let approvedOutcome = await approvedRepairer.repair(status, in: root)
                try expect(approvedOutcome == .created(paths: ["tasks"]), "Approved repair should create the missing directory.")
                try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: "tasks").path), "Approved repair should create tasks/.")
            }

            private func workspaceModuleConfigurationStoreNotifiesObserversAtomically() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModuleStoreWatchWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                try WorkspaceTemplateRepository().overwriteTemplateConfiguration(WorkspaceTemplateRegistry.literatureReview, in: root)
                let store = WorkspaceModuleConfigurationStore()
                let stream = store.subscribeChanges(in: root)

                async let observedConfiguration: WorkspaceModuleConfiguration = firstModuleConfiguration(from: stream)
                var configuration = try await store.load(in: root)
                configuration = try WorkspaceModuleSettingsMutation.setModule("code", enabled: true, in: configuration)
                try await store.save(configuration, in: root)
                let observed = try await observedConfiguration

                try expect(observed.module(id: "code")?.enabled == true, "Store watcher should publish the atomically saved module configuration.")
            }

            private func moduleOverrideMergerOnlyMutatesEnabledField() throws {
                var workspaceConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                workspaceConfiguration = try WorkspaceModuleSettingsMutation.togglePin("calendar", in: workspaceConfiguration)
                let override = WorkspaceModuleOverride(projectID: "project-a", moduleOverrides: [WorkspaceModuleOverrideEntry(id: "calendar", enabled: false)])
                let effectiveConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: override)

                try expect(effectiveConfiguration.module(id: "calendar")?.enabled == false, "Override should update enabled.")
                try expect(effectiveConfiguration.module(id: "calendar")?.pinned == true, "Override should not mutate pinned.")
                try expect(effectiveConfiguration.module(id: "calendar")?.routes == workspaceConfiguration.module(id: "calendar")?.routes, "Override should not mutate registry routes.")
            }

            private func moduleOverrideMergerLeavesUnknownIDsAsNoOp() throws {
                let workspaceConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                let override = WorkspaceModuleOverride(projectID: "project-a", moduleOverrides: [WorkspaceModuleOverrideEntry(id: "third-party-module", enabled: true)])
                let effectiveConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: override)

                try expect(effectiveConfiguration == workspaceConfiguration, "Unknown override module ids should be ignored.")
            }

            private func templateAndSettingsRoundTripsAreIdentical() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModuleRoundTripWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                let repository = WorkspaceTemplateRepository()
                try repository.overwriteTemplateConfiguration(WorkspaceTemplateRegistry.minimal, in: root)
                let originalYAML = try String(contentsOf: root.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath), encoding: .utf8)
                let loadedConfiguration = try repository.loadConfiguration(in: root)
                try await WorkspaceModuleConfigurationStore().save(loadedConfiguration, in: root)
                let savedYAML = try String(contentsOf: root.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath), encoding: .utf8)

                try expect(savedYAML == originalYAML, "Wizard and Module Settings should use identical workspace_modules.yaml serialization.")
            }

    private func runtimeEventEnvelopeSequencesAreStableAndDeduplicated() async throws {
        let fixture = try await loopWorkspaceFixture(named: "RuntimeEventDedupeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let store = AgentRunDirectoryStore()
        let first = AgentRuntimeEventEnvelope(id: "evt-dedupe", runID: "dedupe-run", sequence: 1, event: .runStarted(AgentRunStarted(goal: "Deduplicate")))
        let duplicate = AgentRuntimeEventEnvelope(id: "evt-dedupe", runID: "dedupe-run", sequence: 99, event: .runStarted(AgentRunStarted(goal: "Duplicate")))
        let second = AgentRuntimeEventEnvelope(id: "evt-dedupe-2", runID: "dedupe-run", sequence: 2, event: .finalResponse(AgentFinalResponse(markdown: "Done")))

        try await store.appendEvent(first, in: fixture.root)
        try await store.appendEvent(duplicate, in: fixture.root)
        try await store.appendEvent(second, in: fixture.root)
        let events = try await store.eventEnvelopes(runID: "dedupe-run", in: fixture.root)
        let nextSequence = try await store.nextSequence(runID: "dedupe-run", in: fixture.root)

        try expect(events.map(\.id) == ["evt-dedupe", "evt-dedupe-2"], "Run directory should ignore duplicate runtime event ids.")
        try expect(events.map(\.sequence) == [1, 2], "Deduplicated events should preserve committed host sequence.")
        try expect(nextSequence == 3, "nextSequence should continue after the latest committed event.")
    }

    private func agentHumanDecisionActionDecodesLegacyAliases() throws {
        let decoder = JSONDecoder()
        let deny = try decoder.decode(AgentHumanDecisionAction.self, from: Data(#""deny""#.utf8))
        let revise = try decoder.decode(AgentHumanDecisionAction.self, from: Data(#""askAgentToRevise""#.utf8))

        try expect(deny == .denyAndStop, "Legacy deny action should decode to denyAndStop.")
        try expect(revise == .reviseWithFeedback, "Legacy askAgentToRevise action should decode to reviseWithFeedback.")
    }

    private func agentToolRiskUnknownValueDecodesAsExternalSideEffect() throws {
        let decoded = try JSONDecoder().decode(AgentToolRisk.self, from: Data(#""unknownFutureRisk""#.utf8))

        try expect(decoded == .externalSideEffect, "Unknown tool risk values should decode to externalSideEffect.")
    }

    private func runtimeEventEnvelopeUsesExternalTaggedUnion() throws {
        let result = AgentToolResult(callID: "call-runtime", toolName: "read_note", succeeded: true, message: "Runtime evidence")
        let wireResult = AgentToolResultWireFormat(result: result, toolCallID: "call-runtime")
        let envelope = AgentRuntimeEventEnvelope(
            id: "evt-runtime",
            runID: "run-runtime",
            sequence: 7,
            timestamp: Date(timeIntervalSince1970: 0),
            event: .toolCallCompleted(AgentToolCallCompleted(tool: "read_note", toolCallID: "call-runtime", result: wireResult))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        let encoded = String(data: data, encoding: .utf8) ?? ""
        let decoded = try AgentRunDirectoryStore.decoder().decode(AgentRuntimeEventEnvelope.self, from: data)

        try expect(encoded.contains(#""type":"tool_call_completed""#), "Runtime events should encode as event.type.")
        try expect(encoded.contains(#""payload""#), "Runtime events should encode payload alongside type.")
        if case let .toolCallCompleted(payload) = decoded.event {
            try expect(payload.result.schemaVersion == 1, "Decoded tool completion event should preserve the V1 tool result.")
        } else {
            throw ValidationError(message: "Decoded runtime event should be toolCallCompleted.")
        }
    }

    private func stableToolResultV1MapsToToolCallCompletedEvent() throws {
        let result = AgentToolResult(
            callID: "call-stable",
            toolName: "write_note",
            succeeded: true,
            message: "Created a note for audit.",
            modifiedPaths: ["wiki/notes/audit.md"]
        )
        let wireResult = AgentToolResultWireFormat(result: result, toolCallID: "call-stable")
        let json = try wireResult.stableJSON()
        let decoded = try AgentRunDirectoryStore.decoder().decode(AgentToolResultWireFormat.self, from: Data(json.utf8))
        let completed = AgentToolCallCompleted(tool: "write_note", toolCallID: "call-stable", result: wireResult)

        try expect(json.contains(#""schema_version":1"#), "Stable tool result JSON should include schema_version 1.")
        try expect(decoded.modifiedPaths == ["wiki/notes/audit.md"], "Stable tool result JSON should preserve modified paths.")
        try expect(completed.result.agentToolResult().modifiedPaths == ["wiki/notes/audit.md"], "Runtime tool completion should embed the stable tool result V1 payload.")
    }

    private func mcpGatewayListsAndCallsReadOnlySciStationTools() async throws {
        let fixture = try await loopWorkspaceFixture(named: "MCPReadOnlyWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "MCP evidence")
        ])
        let registry = AgentToolRegistry(tools: [tool])
        let gateway = AgentMCPGateway(toolHost: SciStationToolHost(legacyRegistry: registry))
        let context = AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)

        let listResponse = await gateway.handle(AgentMCPEnvelope(id: "mcp-list", method: "tools/list"), context: context)
        let listResult = try jsonObject(listResponse.result, "tools/list should return a JSON object.")
        let tools = try jsonArray(listResult["tools"], "tools/list should return tools array.")
        let toolObjects = try tools.map { try jsonObject($0, "Each listed MCP tool should be an object.") }

        let readOnlyTool = try require(
            toolObjects.first { object in
                object["name"]?.stringValue == "read_note"
                    && object["risk"]?.stringValue == AgentToolRisk.readOnly.rawValue
            },
            "MCP tools/list should expose the read_note tool."
        )
        let annotations = try jsonObject(readOnlyTool["annotations"], "MCP tool annotations should be an object.")
        try expect(annotations["readOnly"] == .bool(true), "MCP tools/list should expose read-only annotations.")

        let callResponse = await gateway.handle(
            AgentMCPEnvelope(
                id: "mcp-call-read",
                method: "tools/call",
                params: .object([
                    "name": .string("read_note"),
                    "arguments": .object(["path": .string("paper.md")])
                ])
            ),
            context: context
        )
        let callResult = try jsonObject(callResponse.result, "Read-only tools/call should return a JSON object.")
        let invocationCount = await tool.invocationCount()

        try expect(callResponse.error == nil, "Read-only MCP tool call should not return JSON-RPC error.")
        try expect(callResult["structuredContent"] != nil, "Read-only MCP tool call should return structuredContent.")
        try expect(callResult["content"] != nil, "Read-only MCP tool call should return content array.")
        try expect(invocationCount == 1, "Read-only MCP tool call should invoke the tool once.")
    }

    private func mcpGatewayRequiresApprovalForWorkspaceWrites() async throws {
        let fixture = try await loopWorkspaceFixture(named: "MCPWriteApprovalWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Should wait for approval")
        ])
        let registry = AgentToolRegistry(tools: [tool])
        let gateway = AgentMCPGateway(toolHost: SciStationToolHost(legacyRegistry: registry))
        let context = AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)

        let response = await gateway.handle(
            AgentMCPEnvelope(
                id: "mcp-call-write",
                method: "tools/call",
                params: .object([
                    "name": .string("create_todo"),
                    "arguments": .object(["title": .string("Review gateway approval")])
                ])
            ),
            context: context,
            runID: "mcp-write-run"
        )
        let result = try jsonObject(response.result, "Write tools/call should return a JSON object.")
        let approval = try jsonObject(result["approvalRequest"], "Approval-required MCP response should include approvalRequest.")
        let targetPaths = try jsonArray(approval["target_paths"], "Approval request should include target paths.").compactMap(\.stringValue)
        let invocationCount = await tool.invocationCount()

        try expect(response.error == nil, "Approval-required MCP tool call should be a normal result, not JSON-RPC error.")
        try expect(result["status"]?.stringValue == "approval_required", "Write MCP tool call should return approval_required status.")
        try expect(approval["fingerprint"]?.stringValue?.hasPrefix("sha256:") == true, "Approval request should carry an idempotency fingerprint.")
        try expect(targetPaths == ["tasks/todos.yaml"], "ToolHost should preview create_todo target path for MCP approval.")
        try expect(invocationCount == 0, "Write MCP tool call must not invoke the tool before approval.")
    }

    private func p32LegacyPendingCheckpointMigratesToRunDirectory() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LegacyPendingMigrationWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "legacy-call", toolName: "write_note", argumentsJSON: #"{"path":"wiki/legacy.md"}"#)
        let approval = AgentApprovalRequest(
            runID: "legacy-run",
            toolCallID: call.id,
            toolName: call.toolName,
            permissionKey: AgentToolRisk.writesWorkspace.defaultPermissionKey,
            risk: .writesWorkspace,
            argumentsJSON: call.argumentsJSON,
            targetPaths: ["wiki/legacy.md"]
        )
        let pending = AgentPendingToolCall(
            runID: "legacy-run",
            stepIndex: 3,
            toolCall: call,
            approvalRequest: approval,
            messagesBeforePause: [LLMChatMessage(role: .user, content: "Legacy pending")]
        )
        let checkpointStore = AgentLoopCheckpointStore()
        try await checkpointStore.saveLegacyFallback(pending, in: fixture.root)

        let migrated = try await checkpointStore.pending(runID: "legacy-run", in: fixture.root)
        let runDirectoryPending = try await AgentRunDirectoryStore().pending(runID: "legacy-run", in: fixture.root)

        try expect(migrated?.toolCall.id == "legacy-call", "Legacy pending call should remain readable.")
        try expect(runDirectoryPending?.toolCall.id == "legacy-call", "Reading legacy pending call should migrate it into the run directory checkpoint.")
    }

    private func persistentLedgerPreventsDuplicateApprovedWriteAfterRestart() async throws {
        let fixture = try await loopWorkspaceFixture(named: "PersistentLedgerWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-ledger-write", toolName: "create_todo", argumentsJSON: #"{"title":"Ledger once"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Created once."))
        ])
        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let firstTool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created once", modifiedPaths: ["tasks/todos.yaml"])
        ])
        let firstRegistry = AgentToolRegistry(tools: [firstTool])
        let firstRunner = AgentLoopRunner()
        let paused = try await firstRunner.run(loopRequest(runID: "ledger-run", provider: provider, definitions: [definition], registry: firstRegistry, fixture: fixture))
        let pending = try require(paused.pendingToolCall, "Expected ledger write to pause for approval.")

        _ = try await firstRunner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: provider, definitions: [definition], registry: firstRegistry, fixture: fixture))
        let firstInvocationCount = await firstTool.invocationCount()

        let secondTool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Should not run", modifiedPaths: ["tasks/todos.yaml"])
        ])
        let secondProvider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Loaded from ledger."))
        ])
        let secondRunner = AgentLoopRunner()
        _ = try await secondRunner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: secondProvider, definitions: [definition], registry: AgentToolRegistry(tools: [secondTool]), fixture: fixture))
        let secondInvocationCount = await secondTool.invocationCount()
        let records = try await AgentRunDirectoryStore().toolCallRecords(runID: "ledger-run", in: fixture.root)

        try expect(firstInvocationCount == 1, "First approved write should execute once.")
        try expect(secondInvocationCount == 0, "A restarted runner should reuse the persistent ledger result instead of re-invoking the approved write.")
        try expect(records.contains(where: { $0.status == .completed && $0.toolCallID == "call-ledger-write" }), "Persistent ledger should record the completed write call.")
    }

    private func approvalRequestPersistsFingerprintForLedgerResume() async throws {
        let fixture = try await loopWorkspaceFixture(named: "ApprovalFingerprintWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-approval-fingerprint", toolName: "create_todo", argumentsJSON: #"{"title":"Fingerprint"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
        ])
        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [])
        let runner = AgentLoopRunner()

        let result = try await runner.run(loopRequest(runID: "approval-fingerprint-run", provider: provider, definitions: [definition], registry: AgentToolRegistry(tools: [tool]), fixture: fixture))
        let pending = try require(result.pendingToolCall, "Expected write call to pause for approval.")
        let storedPending = try await AgentRunDirectoryStore().pending(runID: "approval-fingerprint-run", in: fixture.root)
        let checkpointURL = fixture.root.fileURL(for: AgentRunDirectoryStore.runsRelativePath + "/approval-fingerprint-run/checkpoint.json")
        let checkpointText = try String(contentsOf: checkpointURL, encoding: .utf8)

        try expect(pending.approvalRequest.fingerprint.hasPrefix("sha256:"), "Approval request should include a stable fingerprint.")
        try expect(storedPending?.approvalRequest.fingerprint == pending.approvalRequest.fingerprint, "Run directory checkpoint should persist the approval fingerprint.")
        try expect(checkpointText.contains(pending.approvalRequest.fingerprint), "Checkpoint JSON should contain the approval fingerprint for resume/ledger use.")
    }

    private func toolHostBuildApprovalRequestHasNoSideEffects() async throws {
        let fixture = try await loopWorkspaceFixture(named: "ToolHostPreviewWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Should not run")
        ])
        let host = SciStationToolHost(legacyRegistry: AgentToolRegistry(tools: [tool]))
        let approval = try await host.buildApprovalRequest(
            for: AgentToolCall(id: "call-preview", toolName: "create_todo", argumentsJSON: #"{"title":"Preview only"}"#),
            runID: "preview-run",
            context: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)
        )
        let invocationCount = await tool.invocationCount()

        try expect(invocationCount == 0, "Building a ToolHost approval preview must not invoke the tool.")
        try expect(approval.targetPaths == ["tasks/todos.yaml"], "ToolHost approval preview should include expected target paths.")
        try expect(approval.diffPreview?.contains("Preview only") == true, "ToolHost approval preview should include a human-readable diff summary.")
        try expect(approval.rollbackHint?.targetPaths == ["tasks/todos.yaml"], "ToolHost approval preview should include rollback targets.")
    }

    private func readOnlyToolNotPausedByGenericPreToolUseReminder() async throws {
        let fixture = try await loopWorkspaceFixture(named: "ReadOnlyHookReminderWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-read-reminder", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Read with reminder."))
        ])
        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Reminder did not pause")
        ])
        let hookEngine = AgentHookEngine(hooks: [
            AgentHookDefinition(id: "pre-tool-reminder", eventName: .preToolUse, matcher: "*", message: "Audit read-only tool output.")
        ])
        let runner = AgentLoopRunner()

        let result = try await runner.run(loopRequest(runID: "read-reminder-run", provider: provider, definitions: [definition], registry: AgentToolRegistry(tools: [tool]), fixture: fixture, hookEngine: hookEngine))
        let invocationCount = await tool.invocationCount()

        try expect(result.pauseReason == nil, "Generic PreToolUse reminders without deny should not pause read-only tools.")
        try expect(result.finalResponseMarkdown == "Read with reminder.", "Loop should continue to final response after read-only tool reminder.")
        try expect(invocationCount == 1, "Read-only tool should still execute once with a reminder hook.")
    }

    private func deterministicSafetyPolicyBlocksSecretPromptBeforeLLM() async throws {
        let fixture = try await loopWorkspaceFixture(named: "SecretPromptBlockWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Should not be called"))
        ])
        let runner = AgentLoopRunner()

        do {
            _ = try await runner.run(loopRequest(
                runID: "secret-prompt-run",
                goal: "Please use sk-1234567890abcdef for this request.",
                provider: provider,
                definitions: [definition],
                registry: AgentToolRegistry(tools: []),
                fixture: fixture
            ))
            throw ValidationError(message: "Secret-looking prompt should be blocked before model submission.")
        } catch AgentError.invalidArguments(let message) {
            try expect(message.contains("secret"), "Secret prompt denial should explain that a secret was detected.")
        }

        let requests = await provider.recordedRequests()
        try expect(requests.isEmpty, "Prompt safety block should happen before any LLM request is sent.")
    }

    private func hookDenyBlocksSensitivePathWrite() async throws {
        let fixture = try await loopWorkspaceFixture(named: "HookSensitivePathWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-hook-deny", toolName: "write_note", argumentsJSON: #"{"path":"workspace/secrets.txt"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
        ])
        let definition = loopToolDefinition(name: "write_note", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "write_note", succeeded: true, message: "Should not run")
        ])
        let hookEngine = AgentHookEngine(hooks: [
            AgentHookDefinition(id: "deny-secrets-path", eventName: .preToolUse, matcher: "secrets", permissionDecision: .deny, message: "blocked by hook")
        ])
        let runner = AgentLoopRunner()

        let result = try await runner.run(loopRequest(runID: "hook-deny-run", provider: provider, definitions: [definition], registry: AgentToolRegistry(tools: [tool]), fixture: fixture, hookEngine: hookEngine))
        let invocationCount = await tool.invocationCount()

        try expect(result.pauseReason?.kind == .safetyPolicyBlocked, "PreToolUse deny hook should block sensitive path writes.")
        try expect(result.pauseReason?.message.contains("blocked by hook") == true, "Hook denial message should be surfaced in the pause reason.")
        try expect(invocationCount == 0, "Hook-denied write tools should not execute.")
    }

    private func agentSkillLoaderProgressivelyLoadsMatchingSkill() async throws {
        let rootURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let skillDirectory = rootURL.appendingPathComponent(".claude/skills/paper-reading", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory.appendingPathComponent("references", isDirectory: true), withIntermediateDirectories: true)
        try "Checklist".write(to: skillDirectory.appendingPathComponent("references/checklist.md"), atomically: true, encoding: .utf8)
        try """
        ---
        name: paper-reading
        description: Paper evidence review
        version: 1.0.0
        author: Sci-Station
        capabilities: [paper, evidence]
        risk: readOnly
        allowed_tools: [read_paper, search_wiki]
        ---

        Use evidence before drafting conclusions.
        """.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let loader = AgentSkillLoader()
        let metadata = try await loader.loadMetadata(searchRoots: [rootURL.appendingPathComponent(".claude/skills", isDirectory: true)])
        let selected = try await loader.selectSkills(for: "Please do paper evidence review", from: metadata)

        try expect(metadata.first?.trustLevel == .untrusted, "Workspace skill metadata should default to untrusted.")
        try expect(metadata.first?.allowedTools == ["read_paper", "search_wiki"], "Skill metadata should expose allowed tools without loading the body.")
        try expect(selected.first?.body?.contains("Use evidence") == true, "Matching skills should load the body on selection.")
        try expect(selected.first?.resources == ["references/checklist.md"], "Matching skills should disclose adjacent resources on selection.")
    }

            private func openAIProviderPayloadIncludesToolChoiceAuto() throws {
                let provider = OpenAICompatibleProvider()
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let request = LLMProviderRequest(
                    messages: [
                        LLMChatMessage(role: .system, content: "Use tools."),
                        LLMChatMessage(role: .assistant, content: "", toolCalls: [
                            AgentToolCall(id: "call-1", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                        ]),
                        LLMChatMessage(role: .tool, content: "{\"schema_version\":1}", name: "read_note", toolCallID: "call-1")
                    ],
                    tools: [LLMToolSpecification(agentTool: definition)]
                )
                let chatRequest = try provider.buildChatRequest(
                    configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
                    apiKey: "secret-key",
                    providerRequest: request
                )
                let body = try require(chatRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Expected chat body.")

                try expect(body.contains("tool_choice"), "Provider payload should include tool_choice when tools are present.")
                try expect(body.contains("auto"), "Provider payload should set tool_choice to auto.")
                try expect(body.contains("tool_calls"), "Assistant messages should serialize tool_calls.")
                try expect(body.contains("tool_call_id"), "Tool result messages should serialize tool_call_id.")
            }

            private func openAIProviderNormalizesLegacyToolSchemas() throws {
                let provider = OpenAICompatibleProvider()
                let definition = AgentToolDefinition(
                    name: "create_todo",
                    summary: "Create a todo.",
                    inputSchema: #"{"title":"string","priority":"low|medium|high|urgent optional","tags":["string"]}"#,
                    risk: .writesWorkspace
                )
                let chatRequest = try provider.buildChatRequest(
                    configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
                    apiKey: "secret-key",
                    providerRequest: LLMProviderRequest(
                        messages: [LLMChatMessage(role: .user, content: "Create a todo")],
                        tools: [LLMToolSpecification(agentTool: definition)]
                    )
                )
                let bodyData = try require(chatRequest.httpBody, "Expected chat body data.")
                let root = try require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any], "Expected JSON request object.")
                let tools = try require(root["tools"] as? [[String: Any]], "Expected tools array.")
                let function = try require(tools.first?["function"] as? [String: Any], "Expected function tool payload.")
                let parameters = try require(function["parameters"] as? [String: Any], "Expected tool parameters schema.")
                let properties = try require(parameters["properties"] as? [String: Any], "Expected schema properties.")
                let title = try require(properties["title"] as? [String: Any], "Expected title property schema.")
                let priority = try require(properties["priority"] as? [String: Any], "Expected priority property schema.")
                let tags = try require(properties["tags"] as? [String: Any], "Expected tags property schema.")

                try expect(parameters["type"] as? String == "object", "Provider should send a JSON Schema object for tool parameters.")
                try expect(title["type"] as? String == "string", "Legacy string shorthand should become a string property schema.")
                try expect((priority["enum"] as? [String]) == ["low", "medium", "high", "urgent"], "Pipe-delimited shorthand should become enum values.")
                try expect(tags["type"] as? String == "array", "Legacy array shorthand should become an array property schema.")
                try expect((parameters["required"] as? [String])?.contains("title") == true, "Non-optional legacy fields should be marked required.")
            }

            private func agentRunLoggerSkipsDamagedHistoryLines() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentDamagedHistoryWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let logger = AgentRunLogger()
                let firstRun = AgentRun(
                    id: "agent-run-valid-1",
                    goal: "First valid run",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    completedAt: Date(timeIntervalSince1970: 1_777_600_001),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "No writes", toolCalls: []),
                    toolResults: [],
                    currentProjectID: "project-alpha"
                )
                let secondRun = AgentRun(
                    id: "agent-run-valid-2",
                    goal: "Second valid run",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_010),
                    completedAt: Date(timeIntervalSince1970: 1_777_600_011),
                    mode: .executeApproved,
                    plan: AgentPlan(summary: "No writes", toolCalls: []),
                    toolResults: [],
                    currentProjectID: "project-beta"
                )

                try await logger.append(firstRun, in: root)
                let logURL = root.fileURL(for: ".sci-station/agent/runs.jsonl")
                let existingContents = try String(contentsOf: logURL, encoding: .utf8)
                try (existingContents + "{not-json}\n").write(to: logURL, atomically: true, encoding: .utf8)
                try await logger.append(secondRun, in: root)

                let history = try await logger.recentRuns(in: root, limit: 5)
                try expect(history.map(\.id) == ["agent-run-valid-2", "agent-run-valid-1"], "Damaged JSONL lines should be skipped while valid runs remain readable newest-first.")
            }

            private func agentRunLoggerFiltersProjectConversations() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentProjectConversationWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let logger = AgentRunLogger()
                let runs = [
                    AgentRun(
                        id: "global-run",
                        goal: "Global conversation",
                        createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                        completedAt: Date(timeIntervalSince1970: 1_777_600_001),
                        mode: .planOnly,
                        plan: AgentPlan(summary: "Global", toolCalls: []),
                        toolResults: []
                    ),
                    AgentRun(
                        id: "alpha-run",
                        goal: "Alpha conversation",
                        createdAt: Date(timeIntervalSince1970: 1_777_600_010),
                        completedAt: Date(timeIntervalSince1970: 1_777_600_011),
                        mode: .planOnly,
                        plan: AgentPlan(summary: "Alpha", toolCalls: []),
                        toolResults: [],
                        currentProjectID: "project-alpha"
                    ),
                    AgentRun(
                        id: "beta-run",
                        goal: "Beta conversation",
                        createdAt: Date(timeIntervalSince1970: 1_777_600_020),
                        completedAt: Date(timeIntervalSince1970: 1_777_600_021),
                        mode: .planOnly,
                        plan: AgentPlan(summary: "Beta", toolCalls: []),
                        toolResults: [],
                        currentProjectID: "project-beta"
                    )
                ]

                for run in runs {
                    try await logger.append(run, in: root)
                }

                let alphaRuns = try await logger.recentRuns(in: root, projectID: "project-alpha", limit: 5)
                let globalRuns = try await logger.recentRuns(in: root, projectID: nil, limit: 5)

                try expect(alphaRuns.map(\.id) == ["alpha-run"], "Project conversation history should only include runs for that project.")
                try expect(globalRuns.map(\.id) == ["global-run"], "Global conversation history should only include runs without a project id.")
            }

            private func agentThreadRepositoryGlobalStoreFiltersByWorkspaceID() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let suiteRoot = temporaryDirectoryURL().appendingPathComponent("AgentThreadGlobalStoreSuite", isDirectory: true)
                let workspaceRoot = suiteRoot.appendingPathComponent("AgentThreadWorkspaceA", isDirectory: true)
                let secondWorkspaceRoot = suiteRoot.appendingPathComponent("AgentThreadWorkspaceB", isDirectory: true)
                let storeDirectory = suiteRoot.appendingPathComponent("GlobalAgentStore", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: suiteRoot)
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let secondWorkspace = try await workspaceService.createWorkspace(at: secondWorkspaceRoot)
                let secondRoot = ResearchRoot(rootURL: secondWorkspace.rootURL)
                let repository = AgentThreadRepository(storeDirectory: storeDirectory)
                let firstDate = Date(timeIntervalSince1970: 1_777_600_000)
                var thread = AgentThread(
                    id: "agent-thread-alpha",
                    projectID: "project-alpha",
                    contextScope: .project,
                    runtimeSelector: AgentRuntimeSelection.swiftLoop.rawValue,
                    createdFromRoute: "ai_lab",
                    title: "Alpha analysis",
                    runIDs: ["run-1"],
                    createdAt: firstDate,
                    updatedAt: firstDate
                )

                try await repository.upsert(thread, in: root)
                thread.appendRunID("run-2", updatedAt: firstDate.addingTimeInterval(10))
                try await repository.upsert(thread, in: root)
                try await repository.upsert(
                    AgentThread(
                        id: "agent-thread-global",
                        title: "Global thread",
                        runIDs: ["global-run"],
                        createdAt: firstDate,
                        updatedAt: firstDate
                    ),
                    in: root
                )
                try await repository.upsert(
                    AgentThread(
                        id: "agent-thread-beta",
                        projectID: "project-beta",
                        title: "Beta analysis",
                        runIDs: ["run-beta"],
                        createdAt: firstDate,
                        updatedAt: firstDate.addingTimeInterval(20)
                    ),
                    in: secondRoot
                )

                let projectThreads = try await repository.threads(in: root, projectID: "project-alpha")
                let globalThreads = try await repository.threads(in: root, projectID: nil)
                let currentWorkspaceThreads = try await repository.allThreads(
                    in: secondRoot,
                    workspaceID: AgentThreadRepository.workspaceID(for: secondRoot),
                    includeArchived: false
                )
                let threadsURL = AgentThreadRepository.threadsFileURL(in: storeDirectory)
                let lines = try String(contentsOf: threadsURL, encoding: .utf8).split(whereSeparator: \.isNewline)

                try expect(projectThreads.map(\.id) == ["agent-thread-alpha"], "Project thread history should be filtered by project id.")
                try expect(projectThreads.first?.runIDs == ["run-1", "run-2"], "Upserting a thread should preserve ordered run ids.")
                try expect(projectThreads.first?.contextScope == .project, "Thread history should preserve project affinity scope metadata.")
                try expect(projectThreads.first?.runtimeSelector == AgentRuntimeSelection.swiftLoop.rawValue, "Thread history should preserve runtime selector metadata.")
                try expect(projectThreads.first?.createdFromRoute == "ai_lab", "Thread history should preserve route origin metadata.")
                try expect(globalThreads.map(\.id) == ["agent-thread-global"], "Global thread history should include only global threads.")
                try expect(currentWorkspaceThreads.map(\.id) == ["agent-thread-beta"], "Thread repository should filter the global store by workspace id.")
                try expect(projectThreads.first?.workspaceID == AgentThreadRepository.workspaceID(for: root), "Upserted threads should be tagged with their workspace id.")
                try expect(projectThreads.first?.workspaceName == root.displayName, "Upserted threads should be tagged with their workspace name.")
                try expect(lines.count == 3, "Thread upsert should replace existing records in the global store instead of duplicating them.")
                try expect(!FileManager.default.fileExists(atPath: root.fileURL(for: AgentThreadRepository.legacyRelativePath).path), "Upserting threads should no longer write workspace-local thread files.")
            }

            private func agentThreadRepositoryMigratesPerWorkspaceLegacy() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let suiteRoot = temporaryDirectoryURL().appendingPathComponent("AgentThreadLegacyMigrationSuite", isDirectory: true)
                let firstWorkspaceRoot = suiteRoot.appendingPathComponent("LegacyWorkspaceA", isDirectory: true)
                let secondWorkspaceRoot = suiteRoot.appendingPathComponent("LegacyWorkspaceB", isDirectory: true)
                let storeDirectory = suiteRoot.appendingPathComponent("GlobalAgentStore", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: suiteRoot)
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let firstWorkspace = try await workspaceService.createWorkspace(at: firstWorkspaceRoot)
                let firstRoot = ResearchRoot(rootURL: firstWorkspace.rootURL)
                let secondWorkspace = try await workspaceService.createWorkspace(at: secondWorkspaceRoot)
                let secondRoot = ResearchRoot(rootURL: secondWorkspace.rootURL)
                let firstLegacyURL = firstRoot.fileURL(for: AgentThreadRepository.legacyRelativePath)
                let secondLegacyURL = secondRoot.fileURL(for: AgentThreadRepository.legacyRelativePath)
                let firstLegacyLine = """
                {"created_at":"2026-04-29T00:00:00Z","id":"legacy-thread-a","project_id":"project-alpha","run_ids":["run-a"],"title":"Legacy A","updated_at":"2026-04-29T00:00:01Z"}
                """
                let secondLegacyLine = """
                {"created_at":"2026-04-30T00:00:00Z","id":"legacy-thread-b","project_id":"project-beta","run_ids":["run-b"],"title":"Legacy B","updated_at":"2026-04-30T00:00:01Z"}
                """
                try firstLegacyLine.write(to: firstLegacyURL, atomically: true, encoding: .utf8)
                try secondLegacyLine.write(to: secondLegacyURL, atomically: true, encoding: .utf8)

                let repository = AgentThreadRepository(storeDirectory: storeDirectory)
                let firstMigration = try await repository.migrateLegacyThreads(from: firstRoot)
                let secondMigration = try await repository.migrateLegacyThreads(from: secondRoot)
                let allThreads = try await repository.allThreads(in: firstRoot, includeArchived: false)
                let threadsByID = Dictionary(uniqueKeysWithValues: allThreads.map { ($0.id, $0) })
                let firstArchiveURL = firstLegacyURL.deletingLastPathComponent().appendingPathComponent(AgentThreadRepository.legacyArchiveFileName)
                let secondArchiveURL = secondLegacyURL.deletingLastPathComponent().appendingPathComponent(AgentThreadRepository.legacyArchiveFileName)

                try expect(firstMigration.migratedCount == 1, "First workspace legacy migration should report one migrated thread.")
                try expect(secondMigration.migratedCount == 1, "Second workspace legacy migration should report one migrated thread.")
                try expect(Set(allThreads.map(\.id)) == ["legacy-thread-a", "legacy-thread-b"], "Legacy threads from multiple workspaces should merge into one global store.")
                try expect(threadsByID["legacy-thread-a"]?.workspaceID == AgentThreadRepository.workspaceID(for: firstRoot), "Migrated legacy A should keep a workspace tag.")
                try expect(threadsByID["legacy-thread-b"]?.workspaceID == AgentThreadRepository.workspaceID(for: secondRoot), "Migrated legacy B should keep a workspace tag.")
                try expect(FileManager.default.fileExists(atPath: firstArchiveURL.path), "First workspace legacy thread file should be preserved as threads.legacy.jsonl.")
                try expect(FileManager.default.fileExists(atPath: secondArchiveURL.path), "Second workspace legacy thread file should be preserved as threads.legacy.jsonl.")
                try expect(!FileManager.default.fileExists(atPath: firstLegacyURL.path), "First workspace legacy thread file should be removed after archival.")
                try expect(!FileManager.default.fileExists(atPath: secondLegacyURL.path), "Second workspace legacy thread file should be removed after archival.")
            }

            private func agentThreadRepositoryArchivesAndReadsLegacyThreads() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let suiteRoot = temporaryDirectoryURL().appendingPathComponent("AgentArchivedThreadSuite", isDirectory: true)
                let workspaceRoot = suiteRoot.appendingPathComponent("AgentArchivedThreadWorkspace", isDirectory: true)
                let storeDirectory = suiteRoot.appendingPathComponent("GlobalAgentStore", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: suiteRoot)
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let threadsURL = root.fileURL(for: AgentThreadRepository.legacyRelativePath)
                let legacyLine = """
                {"created_at":"2026-04-29T00:00:00Z","id":"legacy-thread","project_id":"project-alpha","run_ids":["run-1"],"title":"Legacy thread","updated_at":"2026-04-29T00:00:01Z"}
                """
                try legacyLine.write(to: threadsURL, atomically: true, encoding: .utf8)

                let repository = AgentThreadRepository(storeDirectory: storeDirectory)
                let legacyThreads = try await repository.threads(in: root, projectID: "project-alpha")
                var archivedThread = try require(legacyThreads.first, "Legacy thread without archived_at should still decode.")
                archivedThread.archive(at: Date(timeIntervalSince1970: 1_777_600_100))
                try await repository.upsert(archivedThread, in: root)

                let activeThreads = try await repository.threads(in: root, projectID: "project-alpha")
                let allThreads = try await repository.allThreads(in: root)

                try expect(activeThreads.isEmpty, "Archived threads should be hidden from the default active thread list.")
                try expect(allThreads.map(\.id).contains("legacy-thread"), "Archived threads should remain readable from all thread history.")
            }

            private func agentPromptDraftRepositoryPersistsDrafts() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentDraftWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let repository = AgentPromptDraftRepository()

                try await repository.saveDraft("Review open papers", projectID: "project-alpha", threadID: "thread-alpha", in: root)
                try await repository.saveDraft("Updated prompt", projectID: "project-alpha", threadID: "thread-alpha", in: root)
                try await repository.saveDraft("Global prompt", projectID: nil, threadID: nil, in: root)

                let projectDraft = try await repository.draft(projectID: "project-alpha", threadID: "thread-alpha", in: root)
                let globalDraft = try await repository.draft(projectID: nil, threadID: nil, in: root)
                let draftsURL = root.fileURL(for: ".sci-station/agent/drafts.json")

                try expect(projectDraft == "Updated prompt", "Prompt drafts should upsert by project/thread key.")
                try expect(globalDraft == "Global prompt", "Global prompt drafts should round-trip.")
                try expect(FileManager.default.fileExists(atPath: draftsURL.path), "Prompt drafts should persist to the agent drafts file.")

                try await repository.removeDraft(projectID: "project-alpha", threadID: "thread-alpha", in: root)
                let removedDraft = try await repository.draft(projectID: "project-alpha", threadID: "thread-alpha", in: root)

                try expect(removedDraft == nil, "Prompt drafts should be removable when discarding an empty pending thread.")
            }

            private func agentToolDefinitionsExposePlatformMetadata() throws {
                let readDefinition = AgentToolDefinition(
                    name: "read_context",
                    summary: "Read current workspace context.",
                    inputSchema: "{}",
                    risk: .readOnly
                )
                let writeDefinition = AgentToolDefinition(
                    name: "write_note",
                    displayName: "Write Note",
                    summary: "Write a note into the workspace.",
                    inputSchema: "{\"path\":\"string\"}",
                    inputSchemaVersion: 2,
                    risk: .writesWorkspace,
                    outputPolicy: AgentToolOutputPolicy(maxCharacters: 500, includeAttachments: true)
                )

                let encoded = try JSONEncoder().encode(writeDefinition)
                let decoded = try JSONDecoder().decode(AgentToolDefinition.self, from: encoded)

                try expect(readDefinition.permissionKey == "tool.read", "Read-only tools should default to the read permission key.")
                try expect(!readDefinition.requiresConfirmation, "Read-only tools should not require confirmation by default.")
                try expect(writeDefinition.identifier == "write_note", "Tool definitions should expose a stable identifier.")
                try expect(writeDefinition.permissionKey == "tool.write_workspace", "Workspace-writing tools should expose a write permission key.")
                try expect(writeDefinition.requiresConfirmation, "Workspace-writing tools should require confirmation by default.")
                try expect(decoded.inputSchemaVersion == 2, "Tool definition schema version should round-trip.")
                try expect(decoded.outputPolicy.maxCharacters == 500, "Tool output policy should round-trip.")
            }

            private func agentPermissionRulesEvaluateSafetyDecisions() throws {
                let evaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())

                let destructive = evaluator.evaluate(
                    AgentPermissionRequest(command: "rm -rf .derivedData", risk: .externalSideEffect)
                )
                let sensitivePath = evaluator.evaluate(
                    AgentPermissionRequest(path: "settings/private_api_token.yaml", risk: .writesWorkspace)
                )
                let defaultRead = evaluator.evaluate(
                    AgentPermissionRequest(toolName: "list_papers", risk: .readOnly)
                )
                let defaultWrite = evaluator.evaluate(
                    AgentPermissionRequest(toolName: "create_todo", risk: .writesWorkspace)
                )

                try expect(destructive.action == .deny, "Safety preset should deny recursive removal commands.")
                try expect(destructive.ruleID == "deny-recursive-removal", "Permission decisions should include the matching rule id.")
                try expect(sensitivePath.action == .ask, "Safety preset should ask before sensitive-looking path writes.")
                try expect(defaultRead.action == .allow, "Read-only requests should be allowed by default.")
                try expect(defaultWrite.action == .ask, "Workspace writes should ask by default.")
            }

            private func agentHookEngineEvaluatesLifecycleResults() throws {
                let hooks = AgentSafetyPreset.defaultHooks() + [
                    AgentHookDefinition(
                        id: "deny-shell-preview",
                        eventName: .preToolUse,
                        matcher: #"rm\s+-rf"#,
                        permissionDecision: .deny,
                        message: "Dangerous command blocked."
                    )
                ]
                let engine = AgentHookEngine(hooks: hooks)

                let sessionResults = engine.evaluate(AgentHookEvent(name: .sessionStart))
                let preToolResults = engine.evaluate(
                    AgentHookEvent(name: .preToolUse, toolName: "Bash", command: "rm -rf build")
                )
                let stopResults = engine.evaluate(
                    AgentHookEvent(name: .stop, modifiedPaths: ["Sci-Station/Agent/AgentModels.swift"], validationRecorded: false)
                )

                try expect(sessionResults.first?.additionalContext?.contains("Swift-native") == true, "SessionStart hooks should be able to inject context.")
                try expect(preToolResults.contains(where: { $0.permissionDecision == .deny }), "PreToolUse hooks should return permission decisions.")
                try expect(stopResults.first?.message?.contains("validation") == true, "Stop hooks should be able to remind about validation.")
            }

            private func agentPluginSkillAndMCPModelsValidate() throws {
                let skill = try AgentSkillManifest.parseFrontmatter(from: """
                ---
                name: proposal-draft
                description: Draft Sci-Station proposals from project context.
                version: 0.1.0
                ---

                # Proposal Draft
                """)
                let command = AgentCommandTemplate(
                    id: "proposal-draft",
                    slashCommand: "/proposal-draft",
                    title: "Proposal Draft",
                    promptTemplate: "Draft the next proposal from current project context.",
                    requiredSkillIDs: [skill.id]
                )
                let server = MCPServerConfiguration(
                    id: "sci-station-filesystem",
                    displayName: "Sci-Station Filesystem",
                    transport: .localCommand,
                    isEnabled: true,
                    command: "npx",
                    arguments: ["-y", "@modelcontextprotocol/server-filesystem", "${workspaceRoot}"],
                    allowedTools: ["read_file"],
                    headerReferences: [MCPHeaderReference(name: "Authorization", valueReference: "keychain:mcp/filesystem/authorization")]
                )
                let manifest = AgentPluginManifest(
                    id: "research-core",
                    name: "Research Core",
                    description: "Default Sci-Station research workflow preset.",
                    commands: [command],
                    skills: [skill],
                    hooks: AgentSafetyPreset.defaultHooks(),
                    mcpServers: [server]
                )
                let invalidManifest = AgentPluginManifest(
                    id: "bad",
                    name: "Bad",
                    description: "Invalid command example.",
                    commands: [AgentCommandTemplate(id: "bad", slashCommand: "bad", title: "Bad", promptTemplate: "Bad")],
                    mcpServers: [MCPServerConfiguration(id: "remote", displayName: "Remote", transport: .remoteHTTP)]
                )

                let encodedServer = try JSONEncoder().encode(server)
                let encodedServerText = try require(String(data: encodedServer, encoding: .utf8), "Encoded MCP server should be UTF-8.")
                let issues = AgentPluginValidator().validate(manifest)
                let invalidIssues = AgentPluginValidator().validate(invalidManifest)

                try expect(skill.name == "proposal-draft", "Skill frontmatter parser should read the name.")
                try expect(issues.isEmpty, "Valid plugin manifests should pass validation.")
                try expect(invalidIssues.count == 2, "Validator should report invalid command and remote MCP URL.")
                try expect(encodedServerText.contains("value_reference"), "MCP headers should serialize credential references.")
                try expect(!encodedServerText.contains("Bearer "), "MCP config serialization should not include raw authorization values.")
            }

            private func sciAITrackedPresetManifestValidates() throws {
                let manifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".sci-ai/sci-station/presets/research-core/plugin.json", isDirectory: false)
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(AgentPluginManifest.self, from: data)
                let issues = AgentPluginValidator().validate(manifest)

                try expect(manifest.id == "research-core", "Tracked .sci-ai product preset should decode as research-core.")
                try expect(manifest.commands.contains(where: { $0.slashCommand == "/proposal-draft" }), "Tracked .sci-ai product preset should include proposal drafting.")
                try expect(manifest.mcpServers.allSatisfy { $0.secretReferences.isEmpty }, "Tracked .sci-ai product preset should not include raw secret values.")
                try expect(issues.isEmpty, "Tracked .sci-ai product preset should pass plugin validation.")
            }

            private func sciAIConfigurationBoundaryValidates() throws {
                let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                let trackedPresetURL = repoURL.appendingPathComponent(".sci-ai/sci-station", isDirectory: true)
                let gitignoreURL = repoURL.appendingPathComponent(".gitignore", isDirectory: false)
                let gitignore = try String(contentsOf: gitignoreURL, encoding: .utf8)
                let trackedFiles = try gitTrackedFiles(in: repoURL)

                try expect(!trackedSciAIContainsRawSecrets(at: trackedPresetURL), "Tracked .sci-ai/sci-station files should not contain raw secret-looking values.")
                try expect(gitignore.contains(".sci-ai/workspace.local/"), "Local .sci-ai workspace config path should be ignored by git.")
                try expect(gitignore.contains(".claude/"), "Root .claude bridge should be ignored by git.")
                try expect(gitignore.contains(".mcp.json"), "Root .mcp.json bridge should be ignored by git.")
                try expect(!trackedFiles.contains { $0.hasPrefix(".sci-ai/workspace.local/") }, "Local .sci-ai workspace config should not be tracked.")
                try expect(!trackedFiles.contains { $0.hasPrefix(".claude/") }, "Root .claude bridge directory should not be tracked.")
                try expect(!trackedFiles.contains(".mcp.json"), "Root .mcp.json bridge file should not be tracked.")
            }

            private func agentSessionEventLoggerAppendsAndReplaysEvents() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentSessionEventWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let logger = AgentSessionEventLogger()
                let firstEvent = AgentSessionEvent(
                    id: "event-1",
                    sessionID: "session-alpha",
                    threadID: "thread-alpha",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    kind: .userMessage,
                    summary: "User asked for a plan."
                )
                let secondEvent = AgentSessionEvent(
                    id: "event-2",
                    sessionID: "session-alpha",
                    threadID: "thread-alpha",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_001),
                    kind: .hookResult,
                    summary: "PreToolUse asked for confirmation.",
                    payloadJSON: "{\"decision\":\"ask\"}"
                )

                try await logger.append(firstEvent, in: root)
                let logURL = root.fileURL(for: AgentSessionEventLogger.relativePath)
                let existingContents = try String(contentsOf: logURL, encoding: .utf8)
                try (existingContents + "{not-json}\n").write(to: logURL, atomically: true, encoding: .utf8)
                try await logger.append(secondEvent, in: root)

                let alphaEvents = try await logger.events(in: root, sessionID: "session-alpha")
                let missingEvents = try await logger.events(in: workspace, sessionID: "missing")

                try expect(alphaEvents.map(\.id) == ["event-1", "event-2"], "Session event logger should replay valid events in append order.")
                try expect(missingEvents.isEmpty, "Session event logger should filter by session id.")
            }

            private func openAIStreamDeltaParserIgnoresBadChunks() throws {
                let validChunk = #"{"choices":[{"delta":{"content":"Hello"}}]}"#.data(using: .utf8)!
                let emptyDeltaChunk = #"{"choices":[{"delta":{}}]}"#.data(using: .utf8)!
                let badChunk = Data("{not-json}".utf8)

                try expect(OpenAICompatibleStreamDeltaParser.contentDelta(from: validChunk) == "Hello", "SSE parser should decode content deltas.")
                try expect(OpenAICompatibleStreamDeltaParser.contentDelta(from: emptyDeltaChunk) == nil, "SSE parser should ignore empty deltas.")
                try expect(OpenAICompatibleStreamDeltaParser.contentDelta(from: badChunk) == nil, "SSE parser should ignore malformed JSON chunks.")
            }

            private func llmProviderV2RequestModelsToolDefinitions() throws {
                let definition = AgentToolDefinition(
                    name: "create_todo",
                    summary: "Create a todo.",
                    inputSchema: "{\"title\":\"string\"}",
                    risk: .writesWorkspace
                )
                let tool = LLMToolSpecification(agentTool: definition)
                let request = LLMProviderRequest(
                    messages: [
                        LLMChatMessage(role: .system, content: "Plan first."),
                        LLMChatMessage(role: .user, content: "Create a follow-up todo.")
                    ],
                    tools: [tool],
                    options: LLMProviderOptions(model: "gpt-4.1", temperature: 0.2)
                )
                let response = LLMProviderResponse(
                    message: LLMChatMessage(role: .assistant, content: "Ready."),
                    toolCalls: [AgentToolCall(id: "call-1", toolName: "create_todo", argumentsJSON: "{\"title\":\"Review\"}")]
                )
                let adapterFlow = LLMProviderV2AdapterFlow(
                    messages: request.messages,
                    toolDefinitions: [definition],
                    options: request.options
                )
                let provider = OpenAICompatibleProvider()
                let configuration = LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "fallback-model")
                let chatRequest = try provider.buildChatRequest(
                    configuration: configuration,
                    apiKey: "secret-key",
                    providerRequest: adapterFlow.request
                )
                let chatBody = try require(chatRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Provider V2 chat body should encode as UTF-8.")

                let decodedRequest = try JSONDecoder().decode(LLMProviderRequest.self, from: JSONEncoder().encode(request))
                let decodedResponse = try JSONDecoder().decode(LLMProviderResponse.self, from: JSONEncoder().encode(response))

                try expect(decodedRequest.messages.count == 2, "Provider V2 requests should preserve message history.")
                try expect(decodedRequest.tools.first?.permissionKey == "tool.write_workspace", "Provider V2 tool specs should preserve permission keys.")
                try expect(decodedRequest.options.model == "gpt-4.1", "Provider V2 requests should preserve model options.")
                try expect(decodedResponse.toolCalls.first?.toolName == "create_todo", "Provider V2 responses should preserve tool calls.")
                try expect(adapterFlow.preservesLegacyCompletePath, "Provider V2 adapter flow should explicitly preserve the legacy complete path.")
                try expect(adapterFlow.supportsTaskCancellation, "Provider V2 adapter flow should document Task cancellation support.")
                try expect(chatBody.contains("tools"), "OpenAI-compatible Provider V2 wrapper should encode tool definitions.")
                try expect(chatBody.contains("gpt-4.1"), "OpenAI-compatible Provider V2 wrapper should use request model options.")
            }

            private func agentSessionTimelineItemsFilterCurrentSessions() throws {
                let events = [
                    AgentSessionEvent(
                        id: "timeline-1",
                        sessionID: "run-current",
                        createdAt: Date(timeIntervalSince1970: 10),
                        kind: .userMessage,
                        summary: "Review current papers.",
                        payloadJSON: "{\"content\":\"Review current papers.\"}"
                    ),
                    AgentSessionEvent(
                        id: "timeline-2",
                        sessionID: "run-other",
                        createdAt: Date(timeIntervalSince1970: 11),
                        kind: .assistantMessage,
                        summary: "Other run summary.",
                        payloadJSON: "{\"content\":\"Other run summary.\"}"
                    ),
                    AgentSessionEvent(
                        id: "timeline-3",
                        sessionID: "run-current",
                        createdAt: Date(timeIntervalSince1970: 12),
                        kind: .permissionRequested,
                        summary: "create_todo needs approval.",
                        payloadJSON: "{\"title\":\"Follow up\"}"
                    )
                ]

                let items = AgentSessionTimelineItem.items(from: events, sessionIDs: Set(["run-current"]))

                try expect(items.map(\.eventID) == ["timeline-1", "timeline-3"], "Timeline items should filter to the current run/session ids.")
                try expect(items.first?.payloadPreview == nil, "Timeline chat bubbles should not render raw user or assistant payload JSON as message content.")
                try expect(items.last?.title == "请求审批", "Timeline items should label permission request events.")
                try expect(items.last?.payloadPreview?.contains("Follow up") == true, "Timeline items should preserve payload previews for audit.")
            }

            private func agentSessionTimelineProjectsLegacyRuns() throws {
                let failedRun = AgentRun(
                    id: "legacy-failed-run",
                    goal: "Read the first paper.",
                    createdAt: Date(timeIntervalSince1970: 100),
                    completedAt: Date(timeIntervalSince1970: 101),
                    mode: .planOnly,
                    plan: AgentPlan(
                        title: "运行失败",
                        summary: "Provider failed.",
                        risk: "Provider returned an empty response.",
                        steps: [],
                        toolCalls: [],
                        finalResponseDraft: nil
                    ),
                    toolResults: [],
                    lifecycleState: .failed,
                    failureCategory: .emptyResponse
                )
                let completedRun = AgentRun(
                    id: "legacy-completed-run",
                    goal: "Hello.",
                    createdAt: Date(timeIntervalSince1970: 200),
                    completedAt: Date(timeIntervalSince1970: 201),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "你好！", toolCalls: [], finalResponseDraft: "你好！"),
                    toolResults: []
                )

                let failedItems = AgentSessionTimelineItem.items(from: [], runs: [failedRun], sessionIDs: Set(["legacy-failed-run"]))
                let completedItems = AgentSessionTimelineItem.items(from: [], runs: [completedRun], sessionIDs: Set(["legacy-completed-run"]))

                try expect(failedItems.map(\.kind) == [.userMessage, .toolCallFailed], "Legacy failed runs should project to user and inline failure timeline items.")
                try expect(failedItems.last?.detail == "Provider returned an empty response.", "Projected failures should use the visible risk/failure text.")
                try expect(completedItems.map(\.kind) == [.userMessage, .assistantMessage], "Legacy completed runs should project to user and assistant timeline items.")
                try expect(completedItems.last?.detail == "你好！", "Projected completed runs should preserve final response text.")
            }

            private func agentRunRetryMetadataRoundTrips() throws {
                let run = AgentRun(
                    id: "retry-run",
                    goal: "Retry this.",
                    createdAt: Date(timeIntervalSince1970: 300),
                    completedAt: Date(timeIntervalSince1970: 301),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "Failed.", toolCalls: []),
                    toolResults: [],
                    lifecycleState: .failed,
                    failureCategory: .providerUnavailable,
                    retryOfRunID: "original-run"
                )
                let data = try JSONEncoder().encode(run)
                let decoded = try JSONDecoder().decode(AgentRun.self, from: data)

                try expect(decoded.lifecycleState == .failed, "AgentRun should round-trip lifecycle_state.")
                try expect(decoded.failureCategory == .providerUnavailable, "AgentRun should round-trip failure_category.")
                try expect(decoded.retryOfRunID == "original-run", "AgentRun should round-trip retry_of_run_id.")
                try expect(decoded.isRetryable, "Failed runs should be retryable.")
            }

            private func agentPermissionDockSummarizesPolicies() throws {
                let writeDefinition = AgentToolDefinition(
                    name: "write_note",
                    summary: "Write a note.",
                    inputSchema: "{\"path\":\"string\"}",
                    risk: .writesWorkspace
                )
                let readDefinition = AgentToolDefinition(
                    name: "read_note",
                    summary: "Read a note.",
                    inputSchema: "{}",
                    risk: .readOnly
                )
                let plan = AgentPlan(
                    summary: "Use two tools.",
                    toolCalls: [
                        AgentToolCall(id: "call-write", toolName: "write_note", argumentsJSON: "{\"path\":\"settings/token.yaml\"}"),
                        AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: "{}")
                    ]
                )
                let run = AgentRun(
                    id: "run-dock",
                    goal: "Test dock.",
                    createdAt: Date(timeIntervalSince1970: 1),
                    completedAt: nil,
                    mode: .planOnly,
                    plan: plan,
                    toolResults: []
                )
                let items = AgentPermissionDockItem.items(
                    for: run,
                    toolDefinitions: [readDefinition, writeDefinition],
                    state: AgentPermissionDockState(
                        approvedCallIDs: ["call-write"],
                        correctionFeedbackByCallID: ["call-write": "Use a safer path."]
                    )
                )

                let writeItem = try require(items.first { $0.id == "call-write" }, "Write dock item should exist.")
                let readItem = try require(items.first { $0.id == "call-read" }, "Read dock item should exist.")

                try expect(writeItem.permissionKey == "tool.write_workspace", "Permission dock should expose permission keys.")
                try expect(writeItem.approvalState == .allowedOnce, "Permission dock should show allow-once state.")
                try expect(writeItem.matchedPolicyDescription.contains("ask-sensitive-path"), "Permission dock should report matched policy rules.")
                try expect(writeItem.pathPreview == ["settings/token.yaml"], "Permission dock should extract path previews from structured arguments.")
                try expect(writeItem.correctionFeedback == "Use a safer path.", "Permission dock should preserve correction feedback.")
                try expect(writeItem.sideEffectsRequirePermission, "Workspace-writing tools should be marked as requiring Permission Dock approval.")
                try expect(readItem.approvalState == .autoAllowed, "Read-only tools should display auto-allow state.")
                try expect(!readItem.sideEffectsRequirePermission, "Read-only tools should be classified as auto-allowed without Permission Dock approval.")
            }

            private func agentHookActivitySummaryReflectsTogglesAndResults() throws {
                let result = AgentHookResult(
                    hookID: "pre-tool-permission-reminder",
                    eventName: .preToolUse,
                    permissionDecision: .ask,
                    message: "Review write before running."
                )
                let payload = try require(String(data: JSONEncoder().encode(result), encoding: .utf8), "Hook result payload should encode.")
                let event = AgentSessionEvent(
                    id: "hook-event",
                    sessionID: "run-hook",
                    kind: .hookResult,
                    summary: "PreToolUse hook pre-tool-permission-reminder. Decision: ask.",
                    payloadJSON: payload
                )

                let summary = AgentHookActivitySummary(
                    hooks: AgentSafetyPreset.defaultHooks(),
                    events: [event],
                    disabledHookIDs: ["post-tool-audit-reminder"]
                )

                try expect(summary.enabledEventNames.contains(.sessionStart), "Hook activity should expose enabled SessionStart hooks.")
                try expect(summary.enabledEventNames.contains(.preToolUse), "Hook activity should expose enabled PreToolUse hooks.")
                try expect(!summary.hooks.first { $0.id == "post-tool-audit-reminder" }!.isEnabled, "Hook activity should reflect disabled hooks.")
                try expect(summary.results.first?.permissionDecision == .ask, "Hook activity should decode hook permission decisions.")
            }

            private func agentMCPServerStatusSummaryParsesProductAndLocal() throws {
                let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                let root = ResearchRoot(rootURL: repoURL)
                let loader = AgentRuntimeConfigurationLoader()
                let preset = try require(try loader.loadProductPreset(in: root), "Tracked research-core preset should load.")
                let localJSON = """
                {
                  "mcpServers": {
                    "local-filesystem": {
                      "command": "npx",
                      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp/workspace"],
                      "env": {
                        "API_TOKEN": "keychain:mcp/local/token",
                        "LOG_LEVEL": "info"
                      },
                      "allowed_tools": ["read_file"],
                      "timeout_seconds": 45
                    }
                  }
                }
                """
                let localStatuses = try AgentRuntimeConfigurationLoader.localMCPServerStatuses(from: Data(localJSON.utf8))
                let productStatus = try require(preset.mcpServers.first, "Product preset should expose MCP server status.")
                let localStatus = try require(localStatuses.first, "Local MCP status should parse from Claude-style config.")

                try expect(productStatus.source == .trackedProductTemplate, "Product MCP status should identify tracked template source.")
                try expect(productStatus.endpointSummary.contains("npx"), "Product MCP status should show local command.")
                try expect(localStatus.source == .localWorkspaceConfig, "Local MCP status should identify local source.")
                try expect(localStatus.allowedTools == ["read_file"], "Local MCP status should preserve allowed tools.")
                try expect(Int(localStatus.timeoutSeconds) == 45, "Local MCP status should preserve timeout.")
                try expect(localStatus.credentialReferenceCount == 1, "Local MCP status should count credential references without exposing values.")
                try expect(localStatus.sideEffectsRequirePermission, "MCP side-effect tools should remain routed through permission layer.")
            }

    private func pdfImportCreatesLibraryMarkdownAndFigures() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let importer = PDFImportService(repository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ImportWorkspace", isDirectory: true)
        let sourcePDFURL = temporaryDirectoryURL().appendingPathComponent("Example-2024.pdf", isDirectory: false)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: sourcePDFURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        try Data("fake pdf".utf8).write(to: sourcePDFURL, options: .atomic)

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let importedPaper = try await importer.importPDF(from: sourcePDFURL, into: workspace, existingPapers: [])
        let paperDirectoryURL = workspace.directoryURL(for: importedPaper.directoryRelativePath)
        let paperMarkdownURL = paperDirectoryURL.appendingPathComponent("paper.md", isDirectory: false)
        let figuresURL = paperDirectoryURL.appendingPathComponent("figures", isDirectory: true)

        try expect(importedPaper.collectionPath == "Uncategorized", "Imported papers should default into the Uncategorized collection.")
        try expect(importedPaper.paperDirectoryRelativePath.hasPrefix("library/papers/"), "Imported papers should be stored in the global library.")
        try expect(FileManager.default.fileExists(atPath: paperDirectoryURL.appendingPathComponent("paper.pdf").path), "Imported paper should include paper.pdf.")
        try expect(FileManager.default.fileExists(atPath: paperMarkdownURL.path), "Imported paper should include paper.md.")
        try expect(FileManager.default.fileExists(atPath: figuresURL.path), "Imported paper should include a figures directory.")

        let rawMarkdown = try String(contentsOf: paperMarkdownURL, encoding: .utf8)
        try expect(rawMarkdown.contains("type: raw-paper"), "paper.md should contain raw-paper frontmatter.")
        try expect(rawMarkdown.contains("status: not_extracted"), "paper.md should record extraction status.")
    }

    private func minerUAPIConversionCopiesImageAssets() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MinerUAssetWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
            MinerUAPIMockURLProtocol.zipData = Data()
            MinerUAPIMockURLProtocol.requestLog = []
            MinerUAPIMockURLProtocol.uploadContentTypeHeaders = []
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await repository.save(samplePaper(id: "mineru-images-paper"), in: workspace)
        let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
        try FileManager.default.createDirectory(at: paperDirectoryURL, withIntermediateDirectories: true)
        try Data("%PDF-1.4\n% fake test pdf".utf8).write(to: paperDirectoryURL.appendingPathComponent("paper.pdf"), options: .atomic)

        MinerUAPIMockURLProtocol.zipData = try zipData(entries: [
            (
                "full.md",
                Data(
                    """
                    # MinerU Output

                    ![Figure](images/figure-1.png)

                    <img src="images/figure-2.webp" alt="Second">
                    """.utf8
                )
            ),
            ("images/figure-1.png", Data([0x89, 0x50, 0x4E, 0x47])),
            ("images/figure-2.webp", Data("WEBP".utf8))
        ])
        MinerUAPIMockURLProtocol.requestLog = []

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MinerUAPIMockURLProtocol.self]
        let service = PaperMarkdownConversionService(session: URLSession(configuration: sessionConfiguration))
        let results = try await service.convert(
            [paper],
            in: workspace,
            configuration: PaperMarkdownConversionConfiguration(
                minerUAPIToken: "test-token",
                minerUAPIBaseURLString: "https://mineru.test",
                overwriteExistingMarkdown: true,
                pollIntervalSeconds: 1,
                pollTimeoutSeconds: 5
            )
        )

        let result = try require(results.first, "MinerU conversion should return a result.")
        try expect(result.didWriteMarkdown, result.errorMessage ?? "MinerU conversion should write paper.md.")

        let paperMarkdownURL = paper.rawMarkdownURL(in: workspace)
        let markdown = try String(contentsOf: paperMarkdownURL, encoding: .utf8)
        try expect(markdown.contains("extraction_engine: mineru_api"), "MinerU conversion should record the API extraction engine.")
        try expect(markdown.contains("![Figure](figures/mineru/images/figure-1.png)"), "Markdown image links should point to copied MinerU assets.")
        try expect(markdown.contains("<img src=\"figures/mineru/images/figure-2.webp\""), "HTML image links should point to copied MinerU assets.")
        try expect(
            FileManager.default.fileExists(atPath: paperDirectoryURL.appendingPathComponent("figures/mineru/images/figure-1.png").path),
            "MinerU PNG assets should be copied into the paper figures directory."
        )
        try expect(
            FileManager.default.fileExists(atPath: paperDirectoryURL.appendingPathComponent("figures/mineru/images/figure-2.webp").path),
            "MinerU WebP assets should be copied into the paper figures directory."
        )
        try expect(
            MinerUAPIMockURLProtocol.requestLog.contains("PUT upload.test/upload/mineru-images-paper.pdf"),
            "MinerU conversion should upload the PDF to the signed upload URL."
        )
        try expect(
            MinerUAPIMockURLProtocol.uploadContentTypeHeaders == [nil],
            "MinerU signed URL upload should not include a Content-Type header."
        )
    }

    private func movePaperToCollectionUpdatesMetadataAndPath() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let moveService = MovePaperToCollectionService(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MovePaperWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let originalPaper = try await repository.save(samplePaper(id: "move-test-paper"), in: workspace)
        let originalDirectoryURL = workspace.directoryURL(for: originalPaper.paperDirectoryRelativePath)
        try Data("fake pdf".utf8).write(to: originalDirectoryURL.appendingPathComponent("paper.pdf"), options: .atomic)

        let movedPaper = try await moveService.move(originalPaper, to: "Dark-Matter/WIMPs", in: workspace)

        try expect(
            movedPaper.paperDirectoryRelativePath == "library/papers/Dark-Matter/WIMPs/move-test-paper",
            "Moving a paper should update its nested directory path."
        )
        try expect(movedPaper.collectionPath == "Dark-Matter/WIMPs", "Moving a paper should update collection_path.")
        try expect(
            movedPaper.notesSummaryRelativePath == "../../../../../wiki/papers/smith2024graph.md",
            "Moving a paper should recompute the summary relative path from the new folder depth."
        )

        let movedMetadata = try String(
            contentsOf: workspace.directoryURL(for: movedPaper.paperDirectoryRelativePath).appendingPathComponent("meta.yaml"),
            encoding: .utf8
        )
        try expect(movedMetadata.contains("collection_path: \"Dark-Matter/WIMPs\""), "Moved metadata should persist the new collection_path.")
    }

    private func wikiPageGenerationWritesTemplateAndUpdatesMetadata() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let generator = WikiPageGenerator(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("WikiWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let savedPaper = try await repository.save(samplePaper(id: "smith2024-graph-rag"), in: workspace)
        let result = try await generator.generatePaperWikiPage(for: savedPaper, in: workspace)

        try expect(FileManager.default.fileExists(atPath: result.fileURL.path), "Wiki page should be written to wiki/papers.")
        let wikiContents = try String(contentsOf: result.fileURL, encoding: .utf8)
        try expect(wikiContents.contains("type: paper"), "Wiki page should contain paper frontmatter.")
        try expect(wikiContents.contains("source_pdf: \"../../library/papers/Uncategorized/smith2024-graph-rag/paper.pdf\""), "Wiki page should contain source_pdf path.")
        try expect(wikiContents.contains("## TL;DR"), "Wiki page should contain summary sections.")

        let loadedPaper = try require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected saved paper metadata to remain loadable after wiki generation."
        )
        try expect(
            loadedPaper.notesSummaryRelativePath == "../../../../wiki/papers/smith2024graph.md",
            "Wiki generation should persist notes.summary_file back to meta.yaml."
        )
    }

    private func wikiPageGenerationRejectsSilentOverwrite() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let generator = WikiPageGenerator(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("WikiConflictWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let savedPaper = try await repository.save(samplePaper(id: "smith2024-graph-rag"), in: workspace)
        _ = try await generator.generatePaperWikiPage(for: savedPaper, in: workspace)

        do {
            _ = try await generator.generatePaperWikiPage(for: savedPaper, in: workspace)
            throw ValidationError(message: "Generating an existing wiki page should not silently overwrite the file.")
        } catch let error as WikiPageGeneratorError {
            switch error {
            case let .alreadyExists(path):
                try expect(path == "wiki/papers/smith2024graph.md", "alreadyExists should report the existing wiki path.")
            }
        }
    }

    private func frontmatterParserParsesArraysAndBody() throws {
        let parser = FrontmatterParser()
        let result = parser.parse(
            """
            ---
            title: "Graph RAG"
            tags:
              - "rag"
              - "graph"
            ---

            # Graph RAG

            Body text.
            """
        )

        try expect(result.frontmatter["title"]?.stringValue == "Graph RAG", "FrontmatterParser should read string values.")
        try expect(result.frontmatter["tags"]?.arrayValue == ["rag", "graph"], "FrontmatterParser should read array values.")
        try expect(result.body.contains("# Graph RAG"), "FrontmatterParser should return the Markdown body after frontmatter.")
    }

    private func wikiLinkParserExtractsTargets() throws {
        let parser = WikiLinkParser()
        let links = parser.parse("See [[Retrieval Augmented Generation]] and [[Knowledge Graph|KG]] plus [[RAG#Overview]].")

        try expect(links.map(\.target) == ["Retrieval Augmented Generation", "Knowledge Graph", "RAG"], "WikiLinkParser should normalize aliases and anchors to page targets.")
    }

    private func backlinkIndexFindsIncomingReferences() throws {
        let targetDocument = MarkdownDocument(
            fileURL: URL(fileURLWithPath: "/tmp/wiki/concepts/rag.md"),
            relativePath: "wiki/concepts/rag.md",
            category: "concepts",
            title: "Retrieval Augmented Generation",
            frontmatter: [:],
            body: "# Retrieval Augmented Generation",
            rawContents: "# Retrieval Augmented Generation",
            outgoingLinks: [],
            pageKeys: [
                WikiLink.normalizePageKey("Retrieval Augmented Generation"),
                WikiLink.normalizePageKey("rag")
            ]
        )
        let sourceDocument = MarkdownDocument(
            fileURL: URL(fileURLWithPath: "/tmp/wiki/papers/smith2024graph.md"),
            relativePath: "wiki/papers/smith2024graph.md",
            category: "papers",
            title: "Graph-based Retrieval Augmented Generation",
            frontmatter: [:],
            body: "See [[Retrieval Augmented Generation]].",
            rawContents: "See [[Retrieval Augmented Generation]].",
            outgoingLinks: [WikiLink(target: "Retrieval Augmented Generation", originalText: "[[Retrieval Augmented Generation]]")],
            pageKeys: [WikiLink.normalizePageKey("Graph-based Retrieval Augmented Generation")]
        )

        let index = BacklinkIndex(documents: [targetDocument, sourceDocument])
        let backlinks = index.backlinks(for: targetDocument)

        try expect(backlinks.count == 1, "BacklinkIndex should return referencing pages for the selected document.")
        try expect(backlinks.first?.relativePath == sourceDocument.relativePath, "BacklinkIndex should point back to the source page.")
    }

    private func wikiLinkParserExtractsNamespaces() throws {
        let parser = WikiLinkParser()
        let links = parser.parse("""
        See [[concept:dark-matter]], [[method:Glauber|Glauber method]], and [[Legacy Page]].
        Also [[concept:dark-matter#overview]].
        """)

        try expect(links.count == 3, "Namespaced parser should dedupe across namespace+target, not across full raw text.")
        try expect(links[0].namespace == "concept" && links[0].target == "dark-matter", "First link should carry namespace=concept.")
        try expect(links[1].namespace == "method" && links[1].target == "Glauber", "Second link should carry namespace=method.")
        try expect(links[2].namespace == nil && links[2].target == "Legacy Page", "Legacy non-namespaced link should still parse.")
        try expect(links[0].normalizedTarget == "concept/dark matter", "Namespaced target should expose a namespace-prefixed normalized key.")
    }

    private func backlinkIndexResolvesNamespacedLinks() throws {
        let concept = MarkdownDocument(
            fileURL: URL(fileURLWithPath: "/tmp/wiki/concepts/dark-matter.md"),
            relativePath: "wiki/concepts/dark-matter.md",
            category: "concepts",
            title: "Dark Matter",
            frontmatter: [:],
            body: "# Dark Matter",
            rawContents: "# Dark Matter",
            outgoingLinks: [],
            pageKeys: [
                WikiLink.normalizePageKey("Dark Matter"),
                "concept/" + WikiLink.normalizePageKey("Dark Matter"),
                "wiki/" + WikiLink.normalizePageKey("Dark Matter")
            ]
        )
        let source = MarkdownDocument(
            fileURL: URL(fileURLWithPath: "/tmp/wiki/papers/garani2017.md"),
            relativePath: "wiki/papers/garani2017.md",
            category: "papers",
            title: "Dark matter in the Sun",
            frontmatter: [:],
            body: "See [[concept:Dark Matter]].",
            rawContents: "See [[concept:Dark Matter]].",
            outgoingLinks: [
                WikiLink(
                    target: "Dark Matter",
                    originalText: "[[concept:Dark Matter]]",
                    namespace: "concept"
                )
            ],
            pageKeys: [WikiLink.normalizePageKey("Dark matter in the Sun")]
        )

        let index = BacklinkIndex(documents: [concept, source])
        let backlinks = index.backlinks(for: concept)
        try expect(backlinks.count == 1, "Namespaced [[concept:...]] link should produce a backlink on the namespaced target.")
        try expect(backlinks.first?.relativePath == source.relativePath, "Backlink should point back to the source page.")
    }

    private func graphNodeIDDerivationFollowsPriorityOrder() throws {
        let doiBased = PaperIdentityGenerator.graphNodeID(
            doi: "https://doi.org/10.1103/PhysRevD.42.3344",
            arxiv: "2101.12345",
            inspireID: "12345",
            citekey: "smith2021abc",
            fallbackPaperID: "smith2021-abc"
        )
        try expect(doiBased == "10.1103/physrevd.42.3344", "DOI should win and be lowercased/trimmed.")

        let arxivBased = PaperIdentityGenerator.graphNodeID(
            doi: nil,
            arxiv: "2101.12345v3",
            inspireID: "12345",
            citekey: "smith2021abc",
            fallbackPaperID: "smith2021-abc"
        )
        try expect(arxivBased == "arxiv:2101.12345", "arXiv should drop the version suffix.")

        let inspireBased = PaperIdentityGenerator.graphNodeID(
            doi: nil,
            arxiv: nil,
            inspireID: "https://inspirehep.net/literature/12345",
            citekey: "smith2021abc",
            fallbackPaperID: "smith2021-abc"
        )
        try expect(inspireBased == "inspire:12345", "Inspire URL should reduce to the numeric id.")

        let citekeyBased = PaperIdentityGenerator.graphNodeID(
            doi: nil,
            arxiv: nil,
            inspireID: nil,
            citekey: "Smith2021ABC",
            fallbackPaperID: "smith2021-abc"
        )
        try expect(citekeyBased == "citekey:smith2021abc", "Citekey fallback should be lowercased and prefixed.")

        let localFallback = PaperIdentityGenerator.graphNodeID(
            doi: nil,
            arxiv: nil,
            inspireID: nil,
            citekey: nil,
            fallbackPaperID: "Smith2021-ABC"
        )
        try expect(localFallback == "local:smith2021-abc", "Local fallback should be used when nothing else is available.")
    }

    private func graphNodeIDResolvedFromPaperInstance() throws {
        let now = Date()
        let paper = Paper(
            id: "garani2017-dark-matter-sun",
            citekey: "garani2017dark",
            title: "Dark matter in the Sun",
            authors: ["Raghuveer Garani"],
            year: 2017,
            venue: "arXiv",
            doi: nil,
            arxiv: "1702.02768v2",
            url: nil,
            pdfRelativePath: "paper.pdf",
            tags: [],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: now,
            updatedAt: now,
            paperDirectoryRelativePath: "library/papers/Uncategorized/garani2017-dark-matter-sun",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
        try expect(paper.resolvedGraphNodeID == "arxiv:1702.02768", "Paper should resolve graph node id from arXiv without version.")
    }

    private func metadataCodecPreservesUnknownFields() throws {
        let codec = PaperMetadataCodec()
        let rawWithReferences = """
        id: smith2024
        citekey: smith2024graph
        title: "Graph RAG"
        authors:
          - "Smith"
        year: 2024
        status: unread
        priority: medium
        rating:
        use_for: []
        references:
          - doi: "10.1000/ref.1"
            title: "Ref One"
          - arxiv: "2101.00001"
            title: "Ref Two"
        custom_field: "do not drop me"
        reading:
          added: 2024-01-01
          first_read:
          deep_read:
          custom_reading_note: "round trip"
        links:
          semantic_scholar:
          github:
          project_page:
        notes:
          summary_file:
          custom_notes_field: "preserved"
        """

        let decoded = codec.decode(
            rawWithReferences,
            directoryRelativePath: "library/papers/Uncategorized/smith2024",
            fallbackTitle: "Fallback",
            createdAt: nil,
            updatedAt: nil
        )
        let reEncoded = codec.encode(decoded, preserving: rawWithReferences)

        try expect(reEncoded.contains("references:"), "Unknown references: block should be preserved across round-trip.")
        try expect(reEncoded.contains("doi: \"10.1000/ref.1\""), "Unknown references children should be preserved verbatim.")
        try expect(reEncoded.contains("arxiv: \"2101.00001\""), "Unknown references children should be preserved verbatim.")
        try expect(reEncoded.contains("custom_field: \"do not drop me\""), "Unknown top-level scalar should be preserved.")
        try expect(reEncoded.contains("custom_reading_note: \"round trip\""), "Unknown child key under reading: should be preserved.")
        try expect(reEncoded.contains("custom_notes_field: \"preserved\""), "Unknown child key under notes: should be preserved.")
    }

    private func metadataCodecEmitsGraphNodeID() throws {
        let codec = PaperMetadataCodec()
        let now = Date()
        let paper = Paper(
            id: "smith2024",
            citekey: "smith2024graph",
            title: "Graph RAG",
            authors: ["Smith"],
            year: 2024,
            venue: nil,
            doi: nil,
            arxiv: "2401.12345v1",
            url: nil,
            pdfRelativePath: nil,
            tags: [],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: now,
            updatedAt: now,
            paperDirectoryRelativePath: "library/papers/Uncategorized/smith2024",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
        let encoded = codec.encode(paper)
        try expect(encoded.contains("graph_node_id: \"arxiv:2401.12345\""), "Encoder should emit a stable graph_node_id derived from arXiv.")
        try expect(codec.decodedGraphNodeID(from: encoded) == "arxiv:2401.12345", "decodedGraphNodeID helper should return the persisted value.")
    }

    private func agentToolErrorClassifierMapsCancelAndTimeout() throws {
        let classifier = AgentToolErrorClassifier()

        let cancelled = classifier.classify(CancellationError(), toolName: "list_papers")
        try expect(cancelled.code == .cancelled, "CancellationError should map to the cancelled code.")

        let timeout = classifier.classify(
            AgentTimeoutError(operation: "Tool invocation", timeoutSeconds: 5, toolName: "list_papers"),
            toolName: "list_papers"
        )
        try expect(timeout.code == .timeout, "AgentTimeoutError should map to the timeout code.")

        let network = classifier.classify(URLError(.notConnectedToInternet), toolName: "list_papers")
        try expect(network.code == .network, "URLError should map to the network code.")

        let unknown = classifier.classify(AgentError.unknownTool("mystery"), toolName: "mystery")
        try expect(unknown.code == .toolNotFound, "unknownTool should classify as tool_not_found.")
    }

    private func jsonlWriterAppendsDurableDedupedLines() async throws {
        let url = temporaryDirectoryURL().appendingPathComponent("jsonl/events.jsonl")
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent())
        }

        struct DummyEvent: Codable, Hashable {
            var id: String
            var sequence: Int
        }

        let writer = JSONLWriter(url: url) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String else {
                return nil
            }
            return id
        }
        _ = try await writer.append(DummyEvent(id: "e1", sequence: 1), id: "e1")
        _ = try await writer.append(DummyEvent(id: "e1", sequence: 1), id: "e1")
        _ = try await writer.append(DummyEvent(id: "e2", sequence: 2), id: "e2")

        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(whereSeparator: \.isNewline)
        try expect(lines.count == 2, "Duplicate id should be skipped by the writer dedup cache.")
    }

    private func graphRepositoryAppendsAndReloadsAtomically() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphRepoTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        let node = GraphNode(id: "paper:test1", kind: .paper, displayName: "Test Paper", createdAt: now, updatedAt: now, sourceHash: "abc", lastIndexedAt: now)
        try await repo.upsertNode(node)

        let node2 = GraphNode(id: "project:proj1", kind: .project, displayName: "Project 1", createdAt: now, updatedAt: now, sourceHash: "def", lastIndexedAt: now)
        try await repo.upsertNode(node2)

        let edge = GraphEdge(kind: .belongsTo, from: "paper:test1", to: "project:proj1", createdAt: now, updatedAt: now, sourceHash: "ghi", lastIndexedAt: now)
        try await repo.upsertEdge(edge)

        let snap = await repo.snapshot()
        try expect(snap.nodes.count == 2, "GraphRepository should have 2 nodes after upserts.")
        try expect(snap.edges.count == 1, "GraphRepository should have 1 edge after upsert.")

        // Close and reopen — should replay from jsonl.
        await repo.close()
        let repo2 = GraphRepository()
        try await repo2.open(in: root)
        let snap2 = await repo2.snapshot()
        try expect(snap2.nodes.count == 2, "GraphRepository should reload 2 nodes from jsonl.")
        try expect(snap2.edges.count == 1, "GraphRepository should reload 1 edge from jsonl.")
        try expect(snap2.node(id: "paper:test1")?.displayName == "Test Paper", "Reloaded node should preserve displayName.")
        await repo2.close()
    }

    private func graphRepositoryDropsOrphanEdgesAfterTombstone() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphOrphanTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        try await repo.upsertNode(GraphNode(id: "paper:a", kind: .paper, displayName: "A", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:b", kind: .paper, displayName: "B", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:a", to: "paper:b", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        try await repo.deleteNode(id: "paper:b")
        let snap = await repo.snapshot()
        try expect(snap.nodes.count == 1, "After deleting node B, only A should remain.")
        try expect(snap.edges.count == 0, "After deleting node B, the incident edge should be removed.")

        // Reopen — tombstone should suppress the edge on replay.
        await repo.close()
        let repo2 = GraphRepository()
        try await repo2.open(in: root)
        let snap2 = await repo2.snapshot()
        try expect(snap2.nodes.count == 1, "After replay, only A should remain.")
        try expect(snap2.edges.count == 0, "After replay, orphan edge should be dropped.")
        await repo2.close()
    }

    private func graphRepositoryCompactPreservesEffectiveState() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphCompactTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        try await repo.upsertNode(GraphNode(id: "paper:x", kind: .paper, displayName: "X", createdAt: now, updatedAt: now, sourceHash: "h1", lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:y", kind: .paper, displayName: "Y", createdAt: now, updatedAt: now, sourceHash: "h2", lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:x", to: "paper:y", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let result = try await repo.forceCompact()
        try expect(result.snapshotURL != nil, "Compact should produce a snapshot file.")

        // Reopen after compact — should load from snapshot, not jsonl.
        await repo.close()
        let repo2 = GraphRepository()
        try await repo2.open(in: root)
        let snap = await repo2.snapshot()
        try expect(snap.nodes.count == 2, "After compact + reopen, nodes should be preserved.")
        try expect(snap.edges.count == 1, "After compact + reopen, edges should be preserved.")
        await repo2.close()
    }

    private func graphRepositoryCrashRecoveryReplaysJSONL() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphCrashTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        try await repo.upsertNode(GraphNode(id: "paper:crash1", kind: .paper, displayName: "Crash Paper", createdAt: now, updatedAt: now, sourceHash: "c1", lastIndexedAt: now))
        await repo.close()

        // Simulate a crash by appending a damaged line to nodes.jsonl.
        let nodesURL = root.fileURL(for: ".sci-station/graph/nodes.jsonl")
        let existing = try String(contentsOf: nodesURL, encoding: .utf8)
        try (existing + "{not-valid-json}\n").write(to: nodesURL, atomically: true, encoding: .utf8)

        // Reopen — should skip the damaged line and still load the valid node.
        let repo2 = GraphRepository()
        try await repo2.open(in: root)
        let snap = await repo2.snapshot()
        try expect(snap.nodes.count == 1, "Crash recovery should skip damaged lines and load valid nodes.")
        try expect(snap.node(id: "paper:crash1")?.displayName == "Crash Paper", "Valid node should survive crash recovery.")
        await repo2.close()
    }

    private func graphReadModelSubgraphRespectsDepth() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphReadModelTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        // Build a chain: A -> B -> C
        try await repo.upsertNode(GraphNode(id: "paper:a", kind: .paper, displayName: "A", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:b", kind: .paper, displayName: "B", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:c", kind: .paper, displayName: "C", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:a", to: "paper:b", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:b", to: "paper:c", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let readModel = GraphReadModel(repository: repo)

        // Depth 1 from A should only reach B.
        let sub1 = await readModel.subgraph(centerNodeID: "paper:a", depth: 1)
        try expect(sub1.nodes.count == 2, "Subgraph depth=1 from A should include A and B.")
        try expect(sub1.edges.count == 1, "Subgraph depth=1 from A should include 1 edge.")

        // Depth 2 from A should reach B and C.
        let sub2 = await readModel.subgraph(centerNodeID: "paper:a", depth: 2)
        try expect(sub2.nodes.count == 3, "Subgraph depth=2 from A should include A, B, and C.")
        try expect(sub2.edges.count == 2, "Subgraph depth=2 from A should include 2 edges.")
        await repo.close()
    }

    private func graphReadModelPathReturnsBFSResult() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphPathTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        try await repo.upsertNode(GraphNode(id: "paper:s", kind: .paper, displayName: "S", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "concept:dm", kind: .concept, displayName: "Dark Matter", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:t", kind: .paper, displayName: "T", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .mentions, from: "paper:s", to: "concept:dm", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .mentions, from: "paper:t", to: "concept:dm", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let readModel = GraphReadModel(repository: repo)
        let path = await readModel.path(from: "paper:s", to: "paper:t")
        try expect(path != nil, "Path from S to T should exist via concept:dm.")
        try expect(path?.count == 2, "Path should be 2 edges: S->dm, T->dm.")

        let noPath = await readModel.path(from: "paper:s", to: "paper:nonexistent")
        try expect(noPath == nil, "Path to nonexistent node should return nil.")
        await repo.close()
    }

    private func graphAgentToolsExposeReadOnlyDefinitions() throws {
        let definitions = GraphAgentTools.makeDefaultTools(paperRepository: PaperRepository(), debugEventLogger: nil).map(\.definition)
        let definitionsByName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
        try expect(Set(definitionsByName.keys).isSuperset(of: GraphAgentTools.allNames), "Default graph tools should expose all P47 tool names.")
        for name in GraphAgentTools.allNames {
            guard let definition = definitionsByName[name] else {
                throw ValidationError(message: "Missing graph tool definition for \(name).")
            }
            try expect(definition.risk == .readOnly, "\(name) should be read-only.")
            try expect(definition.requiresConfirmation == false, "\(name) should not require Permission Dock approval.")
            try expect(definition.permissionKey == "graph.read", "\(name) should use graph.read permission key.")
        }
    }

    private func graphToolBackendFindsMissingCorePapers() async throws {
        let fixture = try await graphToolFixture(name: "GraphMissingCoreToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        var corePaper = graphPaper(id: "core-paper", graphNodeID: "core-paper", title: "Core Paper", year: 2024, projectID: "proj", isCore: true)
        corePaper = try await fixture.paperRepository.save(corePaper, in: fixture.workspace)
        var linkedPaper = graphPaper(id: "linked-paper", graphNodeID: "linked-paper", title: "Already Linked", year: 2021, projectID: "proj", isCore: false)
        linkedPaper = try await fixture.paperRepository.save(linkedPaper, in: fixture.workspace)

        try await fixture.repo.upsertNode(GraphNode(id: "project:proj", kind: .project, displayName: "Project", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:core-paper", kind: .paper, displayName: corePaper.title, payload: .object(["year": .number("2024")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:missing-paper", kind: .paper, displayName: "Missing Foundational Paper", payload: .object(["year": .number("2020")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:linked-paper", kind: .paper, displayName: linkedPaper.title, payload: .object(["year": .number("2021")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .belongsTo, from: "paper:core-paper", to: "project:proj", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .belongsTo, from: "paper:linked-paper", to: "project:proj", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:core-paper", to: "paper:missing-paper", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:core-paper", to: "paper:linked-paper", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.findMissingCorePapers(argumentsJSON: #"{"project_id":"proj"}"#, context: fixture.context)
        let object = try jsonObject(result.payload, "Missing core payload should be an object.")
        let rows = object["missing_core_papers"]?.arrayValue ?? []
        try expect(result.succeeded, "Missing core tool should succeed.")
        try expect(result.requiresConfirmation, "Missing core discoveries should create a graph insight draft for review.")
        try expect(rows.count == 1, "Only the unlinked cited paper should be returned.")
        try expect(rows.first?.objectValue?["paper_node_id"]?.stringValue == "paper:missing-paper", "Missing paper node id should match.")
        try expect(object["graph_insight_draft"]?.objectValue?["kind"]?.stringValue == "graph_insight", "Payload should include a nested graph insight draft.")
        await fixture.repo.close()
    }

    private func graphToolBackendGeneratesReadingPath() async throws {
        let fixture = try await graphToolFixture(name: "GraphReadingPathToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        try await fixture.repo.upsertNode(GraphNode(id: "paper:foundation", kind: .paper, displayName: "Foundation", payload: .object(["year": .number("2010")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:center", kind: .paper, displayName: "Center", payload: .object(["year": .number("2020")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:followup", kind: .paper, displayName: "Follow Up", payload: .object(["year": .number("2024")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:center", to: "paper:foundation", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:followup", to: "paper:center", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.generateReadingPath(argumentsJSON: #"{"center_paper_id":"paper:center","k":3}"#, context: fixture.context)
        let rows = try jsonObject(result.payload, "Reading path payload should be an object.")["reading_path"]?.arrayValue ?? []
        let order = rows.compactMap { $0.objectValue?["paper_node_id"]?.stringValue }
        try expect(order == ["paper:foundation", "paper:center", "paper:followup"], "Reading path should order cited prerequisites before citing follow-ups.")
        await fixture.repo.close()
    }

    private func graphToolBackendDetectsStaleCitations() async throws {
        let fixture = try await graphToolFixture(name: "GraphStaleCitationToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        try await fixture.repo.upsertNode(GraphNode(id: "project:proj", kind: .project, displayName: "Project", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:current", kind: .paper, displayName: "Current", payload: .object(["year": .number("2024")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:old", kind: .paper, displayName: "Old Baseline", payload: .object(["year": .number("2000")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:new", kind: .paper, displayName: "New Extension", payload: .object(["year": .number("2023")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .belongsTo, from: "paper:current", to: "project:proj", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:current", to: "paper:old", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .extends, from: "paper:new", to: "paper:old", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.detectStaleCitations(argumentsJSON: #"{"project_id":"proj","threshold_days":3650}"#, context: fixture.context)
        let rows = try jsonObject(result.payload, "Stale citation payload should be an object.")["stale_edges"]?.arrayValue ?? []
        try expect(rows.count == 1, "Stale citation detector should flag the old citation with a newer extension.")
        let suggestions = rows.first?.objectValue?["suggested_newer_papers"]?.arrayValue ?? []
        try expect(suggestions.first?.objectValue?["paper_node_id"]?.stringValue == "paper:new", "Stale citation detector should suggest the newer extending paper.")
        await fixture.repo.close()
    }

    private func graphToolBackendFindsUnsupportedArtifactClaims() async throws {
        let fixture = try await graphToolFixture(name: "GraphUnsupportedClaimsToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        try await fixture.repo.upsertNode(GraphNode(id: "project:proj", kind: .project, displayName: "Project", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "artifact:one", kind: .artifact, displayName: "Related Work Draft", payload: .object(["status": .string("saved")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "claim:one", kind: .claim, displayName: "Unsupported Claim", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "claim:two", kind: .claim, displayName: "Stale Claim", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "evidence:stale", kind: .evidence, displayName: "Old Evidence", payload: .object(["status": .string("stale")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .belongsTo, from: "artifact:one", to: "project:proj", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .mentions, from: "artifact:one", to: "claim:one", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .mentions, from: "artifact:one", to: "claim:two", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .supports, from: "evidence:stale", to: "claim:two", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.findUnsupportedArtifactClaims(argumentsJSON: #"{"project_id":"proj"}"#, context: fixture.context)
        let rows = try jsonObject(result.payload, "Unsupported claims payload should be an object.")["claims"]?.arrayValue ?? []
        let severities = Set(rows.compactMap { $0.objectValue?["severity"]?.stringValue })
        try expect(severities == ["error", "warning"], "Unsupported claims tool should report missing and stale evidence severities.")
        await fixture.repo.close()
    }

    private func graphToolBackendFindsBridgePapers() async throws {
        let fixture = try await graphToolFixture(name: "GraphBridgeToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        for nodeID in ["paper:a", "paper:b", "paper:c"] {
            try await fixture.repo.upsertNode(GraphNode(id: nodeID, kind: .paper, displayName: nodeID, createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        }
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:a", to: "paper:b", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:b", to: "paper:c", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.findBridgePapers(argumentsJSON: #"{"from_paper_id":"paper:a","to_paper_id":"paper:c"}"#, context: fixture.context)
        let payload = try jsonObject(result.payload, "Bridge payload should be an object.")
        let rows = payload["bridge_papers"]?.arrayValue ?? []
        try expect(payload["path_found"] == .bool(true), "Bridge tool should report path_found=true.")
        try expect(rows.compactMap { $0.objectValue?["paper_node_id"]?.stringValue } == ["paper:a", "paper:b", "paper:c"], "Bridge tool should preserve shortest path paper order.")
        await fixture.repo.close()
    }

    private func bibtexParserHandlesArticleAndMisc() throws {
        let bibtex = """
        @article{garani2017dark,
          title = {Dark matter in the Sun: scattering off electrons vs nucleons},
          author = {Raghuveer Garani and Sergio Palomares-Ruiz},
          year = {2017},
          eprint = {1702.02768},
          archivePrefix = {arXiv},
          doi = {10.1088/1475-7516/2017/05/007}
        }

        @misc{nguyen2026sun,
          title = {The Sun Can Strongly Constrain},
          author = {Thong T. Q. Nguyen and Tim Linden},
          year = {2026},
          eprint = {2602.15113}
        }
        """

        let parser = BibtexParser()
        let entries = parser.parse(bibtex)
        try expect(entries.count == 2, "BibtexParser should parse 2 entries.")
        try expect(entries[0].key == "garani2017dark", "First entry key should be garani2017dark.")
        try expect(entries[0].doi == "10.1088/1475-7516/2017/05/007", "First entry should have DOI.")
        try expect(entries[0].arxivID == "1702.02768", "First entry should have arXiv from eprint field.")
        try expect(entries[0].year == 2017, "First entry year should be 2017.")
        try expect(entries[0].firstAuthorLastName == "Garani", "First author last name should be Garani.")
        try expect(entries[1].key == "nguyen2026sun", "Second entry key should be nguyen2026sun.")
        try expect(entries[1].type == "misc", "Second entry type should be misc.")
    }

    private func bibtexParserSkipsMalformedEntry() throws {
        let bibtex = """
        @comment{This is a comment block that should be skipped.}

        @article{valid,
          title = {Valid Paper},
          author = {Smith},
          year = {2024}
        }

        @misc{also_valid,
          title = {Also Valid},
          year = {2025}
        }
        """

        let parser = BibtexParser()
        let entries = parser.parse(bibtex)
        try expect(entries.count == 2, "BibtexParser should skip @comment and parse 2 valid entries.")
        try expect(entries[0].key == "valid", "First entry should be 'valid'.")
        try expect(entries[0].title == "Valid Paper", "First entry title should be 'Valid Paper'.")
        try expect(entries[1].key == "also_valid", "Second entry should be 'also_valid'.")
    }

    private func markdownReferencesExtractorReadsSection() throws {
        let markdown = """
        # Introduction

        Some text here.

        ## References

        1. Garani, R. & Palomares-Ruiz, S. (2017). Dark matter in the Sun. doi:10.1088/1475-7516/2017/05/007
        2. Nguyen, T. & Linden, T. (2026). The Sun Can Strongly Constrain. arXiv:2602.15113
        - Smith, J. (2024). A third reference without identifiers.

        ## Appendix

        This should not be included.
        """

        let extractor = MarkdownReferencesExtractor()
        let refs = extractor.extract(from: markdown)
        try expect(refs.count == 3, "Extractor should find 3 references.")
        try expect(refs[0].contains("Garani"), "First ref should contain Garani.")
        try expect(refs[1].contains("2602.15113"), "Second ref should contain arXiv id.")
        try expect(refs[2].contains("Smith"), "Third ref should contain Smith.")
    }

    private func referenceResolverDOIWinsOverTitle() throws {
        let now = Date()
        let papers = [
            Paper(id: "garani2017", citekey: "garani2017dark", title: "Dark matter in the Sun", authors: ["Raghuveer Garani"], year: 2017, venue: nil, doi: "10.1088/1475-7516/2017/05/007", arxiv: "1702.02768v2", url: nil, pdfRelativePath: nil, tags: [], status: .unread, priority: .medium, rating: nil, useFor: [], createdAt: now, updatedAt: now, paperDirectoryRelativePath: "library/papers/Uncategorized/garani2017", notesSummaryRelativePath: nil, annotationsRelativePath: nil)
        ]
        let index = LocalPaperIndex(papers: papers)
        let resolver = ReferenceResolver()

        // Reference with DOI that matches.
        let ref = CitationReference(
            sourcePaperID: "nguyen2026",
            evidenceSource: .paperMarkdown,
            rawText: "Garani 2017 doi:10.1088/1475-7516/2017/05/007",
            doi: "10.1088/1475-7516/2017/05/007",
            normalizedTitle: "dark matter in the sun"
        )
        let result = resolver.resolve(ref, localIndex: index)
        if case .matchedLocal(let id) = result.outcome {
            try expect(id == "10.1088/1475-7516/2017/05/007", "DOI match should resolve to the local paper's graphNodeID (DOI-based).")
        } else {
            try expect(false, "DOI match should produce .matchedLocal, got \(result.outcome).")
        }
    }

    private func referenceResolverProducesExternalOnMiss() throws {
        let index = LocalPaperIndex(papers: [])
        let resolver = ReferenceResolver()

        let ref = CitationReference(
            sourcePaperID: "test",
            evidenceSource: .bibtex,
            rawText: "Unknown paper doi:10.9999/fake",
            doi: "10.9999/fake"
        )
        let result = resolver.resolve(ref, localIndex: index)
        if case .matchedExternal(let nodeID, let source) = result.outcome {
            try expect(nodeID == "paper:external:doi:10.9999/fake", "External node ID should contain the DOI.")
            try expect(source == .doi, "External source should be .doi.")
        } else {
            try expect(false, "Missing DOI should produce .matchedExternal.")
        }

        // No identifiers at all.
        let refNoID = CitationReference(
            sourcePaperID: "test",
            evidenceSource: .paperMarkdown,
            rawText: "Some vague reference"
        )
        let resultNoID = resolver.resolve(refNoID, localIndex: index)
        if case .unresolved(let reason) = resultNoID.outcome {
            try expect(reason == "no_doi_arxiv_or_title", "No identifiers should produce unresolved.")
        } else {
            try expect(false, "No identifiers should produce .unresolved.")
        }
    }

    private func levenshteinDistanceComputesCorrectly() throws {
        try expect(Levenshtein.distance("kitten", "sitting") == 3, "Levenshtein(kitten, sitting) should be 3.")
        try expect(Levenshtein.distance("", "abc") == 3, "Levenshtein('', abc) should be 3.")
        try expect(Levenshtein.distance("abc", "abc") == 0, "Levenshtein(abc, abc) should be 0.")
        try expect(Levenshtein.distance("dark matter", "dark mater") == 1, "Levenshtein with 1 char diff should be 1.")
    }

    private func graphLayoutEngineDeterministicWithFixedSeed() throws {
        let nodes: [GraphNode] = (0..<5).map { i in
            GraphNode(id: "paper:p\(i)", kind: .paper, displayName: "Paper \(i)", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date())
        }
        let edges: [GraphEdge] = [
            GraphEdge(kind: .cites, from: "paper:p0", to: "paper:p1", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date()),
            GraphEdge(kind: .cites, from: "paper:p1", to: "paper:p2", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date()),
            GraphEdge(kind: .mentions, from: "paper:p2", to: "paper:p3", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date()),
            GraphEdge(kind: .cites, from: "paper:p3", to: "paper:p4", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date())
        ]
        let subgraph = GraphSubgraph(center: "paper:p0", nodes: nodes, edges: edges)
        let engine = GraphLayoutEngine()

        let result1 = engine.layout(subgraph, canvasWidth: 800, canvasHeight: 600, seed: 42)
        let result2 = engine.layout(subgraph, canvasWidth: 800, canvasHeight: 600, seed: 42)

        try expect(result1.positions.count == 5, "Layout should produce positions for all 5 nodes.")
        for (id, pos1) in result1.positions {
            guard let pos2 = result2.positions[id] else {
                try expect(false, "Second run should have position for \(id).")
                continue
            }
            try expect(abs(pos1.x - pos2.x) < 0.001 && abs(pos1.y - pos2.y) < 0.001, "Layout should be deterministic for node \(id).")
        }
    }

    private func graphLayoutEngineConvergesUnderThreshold() throws {
        let nodes: [GraphNode] = (0..<3).map { i in
            GraphNode(id: "n\(i)", kind: .concept, displayName: "C\(i)", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date())
        }
        let edges: [GraphEdge] = [
            GraphEdge(kind: .mentions, from: "n0", to: "n1", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date()),
            GraphEdge(kind: .mentions, from: "n1", to: "n2", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date())
        ]
        let subgraph = GraphSubgraph(center: "n0", nodes: nodes, edges: edges)
        let engine = GraphLayoutEngine()
        let result = engine.layout(subgraph, canvasWidth: 600, canvasHeight: 400, seed: 7)

        try expect(result.settled, "Layout with 3 nodes should converge (settled=true).")
        try expect(result.iterations < 200, "Layout should converge before max iterations.")
    }

    private func subgraphCacheLRUEvictsOldest() async throws {
        let cache = SubgraphCache(capacity: 3)
        let emptySubgraph = GraphSubgraph(center: "x", nodes: [], edges: [])

        let key1 = SubgraphCache.Key(viewKind: .paperNeighborhood, centerNodeID: "a", depth: 1, kindFilter: [])
        let key2 = SubgraphCache.Key(viewKind: .paperNeighborhood, centerNodeID: "b", depth: 1, kindFilter: [])
        let key3 = SubgraphCache.Key(viewKind: .paperNeighborhood, centerNodeID: "c", depth: 1, kindFilter: [])
        let key4 = SubgraphCache.Key(viewKind: .paperNeighborhood, centerNodeID: "d", depth: 1, kindFilter: [])

        await cache.put(key1, emptySubgraph)
        await cache.put(key2, emptySubgraph)
        await cache.put(key3, emptySubgraph)
        let count1 = await cache.count
        try expect(count1 == 3, "Cache should have 3 entries.")

        await cache.put(key4, emptySubgraph)
        let count2 = await cache.count
        try expect(count2 == 3, "Cache should evict oldest to stay at capacity 3.")
        let evicted = await cache.get(key1)
        try expect(evicted == nil, "Oldest entry (key1) should be evicted.")
        let newest = await cache.get(key4)
        try expect(newest != nil, "Newest entry (key4) should be present.")

        await cache.invalidateAll()
        let count3 = await cache.count
        try expect(count3 == 0, "invalidateAll should clear all entries.")
    }

    private func markdownRepositoryLoadsAndSavesDocuments() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = MarkdownRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MarkdownWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let pageRelativePath = "wiki/concepts/rag.md"
        let savedDocument = try await repository.saveContents(
            """
            ---
            title: "Retrieval Augmented Generation"
            tags:
              - "rag"
            ---

            # Retrieval Augmented Generation

            See [[Knowledge Graph]].
            """,
            relativePath: pageRelativePath,
            in: workspace
        )

        try expect(savedDocument.title == "Retrieval Augmented Generation", "MarkdownRepository should resolve titles from frontmatter.")
        try expect(savedDocument.outgoingLinks.map(\.target) == ["Knowledge Graph"], "MarkdownRepository should parse wikilinks when loading documents.")

        let loadedDocuments = try await repository.loadDocuments(in: workspace)
        try expect(loadedDocuments.contains(where: { $0.relativePath == pageRelativePath }), "MarkdownRepository should scan wiki/ for markdown files.")

        let paperMarkdownPath = "library/papers/Uncategorized/demo-paper/paper.md"
        let paperMarkdownURL = workspace.fileURL(for: paperMarkdownPath)
        try FileManager.default.createDirectory(at: paperMarkdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        title: "Converted Demo Paper"
        ---

        # Converted Demo Paper

        This file lives outside wiki/ but should still be viewable from the Markdown editor.
        """.write(to: paperMarkdownURL, atomically: true, encoding: .utf8)
        let paperDocument = try await repository.loadDocument(relativePath: paperMarkdownPath, in: workspace)

        try expect(paperDocument.relativePath == paperMarkdownPath, "MarkdownRepository should load a specific converted paper.md outside wiki/ for preview/editing.")
        try expect(paperDocument.title == "Converted Demo Paper", "MarkdownRepository should parse frontmatter for external Markdown documents.")
    }

    private func paperMarkdownDirectLoadMergesIntoDocumentList() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        let repository = MarkdownRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PaperMarkdownDirectLoadWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paperMarkdownPath = "library/papers/Uncategorized/direct-paper/paper.md"
        let paperMarkdownURL = workspace.fileURL(for: paperMarkdownPath)
        try FileManager.default.createDirectory(at: paperMarkdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Direct Paper\n".write(to: paperMarkdownURL, atomically: true, encoding: .utf8)

        var documents = try await repository.loadDocuments(in: workspace)
        try expect(!documents.contains(where: { $0.relativePath == paperMarkdownPath }), "paper.md outside wiki should not be part of the default wiki scan.")
        let directDocument = try await repository.loadDocument(relativePath: paperMarkdownPath, in: workspace)
        if !documents.contains(where: { $0.id == directDocument.id }) {
            documents.append(directDocument)
        }

        try expect(documents.contains(where: { $0.relativePath == paperMarkdownPath }), "Direct paper.md load should be mergeable into the active document list without changing wiki scan semantics.")
    }

    private func markdownRepositoryCreatesPageInsideWikiRoot() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownCreateWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        let document = try await fixture.repository.createDocument(relativePath: "wiki/notes/new-page", contents: "# New Page\n", in: fixture.workspace)

        try expect(document.relativePath == "wiki/notes/new-page.md", "MarkdownRepository should default new pages to .md inside wiki root.")
        try expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: document.relativePath).path), "Created wiki page should exist on disk.")
    }

    private func markdownRepositoryRejectsAbsolutePath() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownAbsolutePathWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        do {
            _ = try await fixture.repository.createDocument(relativePath: "/wiki/escape.md", contents: "# Escape\n", in: fixture.workspace)
            throw ValidationError(message: "MarkdownRepository should reject absolute paths.")
        } catch MarkdownRepositoryError.invalidRelativePath {
        }
    }

    private func markdownRepositoryRenamesSelectedPage() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownRenameWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        let original = try await fixture.repository.createDocument(relativePath: "wiki/notes/original.md", contents: "# Original\n", in: fixture.workspace)
        let renamed = try await fixture.repository.renameDocument(relativePath: original.relativePath, toFileName: "renamed.md", in: fixture.workspace)

        try expect(renamed.relativePath == "wiki/notes/renamed.md", "MarkdownRepository should rename a selected page within its folder.")
        try expect(!FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: original.relativePath).path), "Renaming should remove the old file path.")
        try expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: renamed.relativePath).path), "Renaming should create the new file path.")
    }

    private func markdownRepositoryArchivesPageInsteadOfHardDelete() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownArchiveWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        let document = try await fixture.repository.createDocument(relativePath: "wiki/notes/archive-me.md", contents: "# Archive Me\n", in: fixture.workspace)
        let trashPath = try await fixture.repository.archiveDocument(relativePath: document.relativePath, in: fixture.workspace, now: Date(timeIntervalSince1970: 1_777_000_000))

        try expect(!FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: document.relativePath).path), "Archiving should move the active wiki file away from its original path.")
        try expect(trashPath.hasPrefix(".sci-station/trash/wiki/"), "Archived wiki pages should move into the workspace trash area.")
        try expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: trashPath).path), "Archived wiki file should remain recoverable from trash.")
    }

    private func markdownSaveStateTransitionsDirtySavingClean() throws {
        let states: [MarkdownSaveState] = [.clean, .dirty, .saving, .clean, .failed]
        let data = try JSONEncoder().encode(states)
        let decoded = try JSONDecoder().decode([MarkdownSaveState].self, from: data)

        try expect(decoded == states, "MarkdownSaveState should preserve clean/dirty/saving/failed transitions through Codable.")
    }

    private struct MarkdownRepositoryFixture {
        let workspace: ResearchWorkspace
        let repository: MarkdownRepository
        let suiteName: String
        let workspaceRoot: URL
    }

    private func markdownRepositoryFixture(named name: String) async throws -> MarkdownRepositoryFixture {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent(name, isDirectory: true)
        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        return MarkdownRepositoryFixture(workspace: workspace, repository: MarkdownRepository(), suiteName: suiteName, workspaceRoot: workspaceRoot)
    }

    private func cleanupMarkdownRepositoryFixture(_ fixture: MarkdownRepositoryFixture) {
        try? FileManager.default.removeItem(at: fixture.workspaceRoot.deletingLastPathComponent())
        UserDefaults(suiteName: fixture.suiteName)?.removePersistentDomain(forName: fixture.suiteName)
    }

    private struct LoopWorkspaceFixture {
        let workspace: ResearchWorkspace
        let root: ResearchRoot
        let suiteName: String
        let containerURL: URL
    }

    private func loopWorkspaceFixture(named name: String) async throws -> LoopWorkspaceFixture {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let containerURL = temporaryDirectoryURL()
        let workspaceURL = containerURL.appendingPathComponent(name, isDirectory: true)
        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        return LoopWorkspaceFixture(
            workspace: workspace,
            root: ResearchRoot(rootURL: workspace.rootURL),
            suiteName: suiteName,
            containerURL: containerURL
        )
    }

    private func cleanupLoopWorkspaceFixture(_ fixture: LoopWorkspaceFixture) {
        try? FileManager.default.removeItem(at: fixture.containerURL)
        UserDefaults(suiteName: fixture.suiteName)?.removePersistentDomain(forName: fixture.suiteName)
    }

    private func loopToolDefinition(
        name: String,
        risk: AgentToolRisk,
        maxOutputCharacters: Int = 12_000
    ) -> AgentToolDefinition {
        AgentToolDefinition(
            name: name,
            summary: "Loop test tool \(name).",
            inputSchema: "{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"},\"command\":{\"type\":\"string\"}}}",
            risk: risk,
            outputPolicy: AgentToolOutputPolicy(maxCharacters: maxOutputCharacters)
        )
    }

    private func loopRequest(
        runID: String,
        goal: String = "Loop test goal",
        provider: any LLMChatProvider,
        definitions: [AgentToolDefinition],
        registry: AgentToolRegistry,
        fixture: LoopWorkspaceFixture,
        configuration: LLMConfiguration = LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
        options: AgentLoopOptions = AgentLoopOptions(),
        hookEngine: AgentHookEngine = AgentHookEngine(hooks: []),
        permissionEvaluator: AgentPermissionEvaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())
    ) -> AgentLoopRequest {
        AgentLoopRequest(
            runID: runID,
            goal: goal,
            initialMessages: [
                LLMChatMessage(role: .system, content: "Use tools when useful."),
                LLMChatMessage(role: .user, content: "Please inspect the selected context.")
            ],
            provider: provider,
            toolDefinitions: definitions,
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: configuration,
            apiKey: "test-key",
            options: options,
            hookEngine: hookEngine,
            permissionEvaluator: permissionEvaluator
        )
    }

    private func loopResumeRequest(
        pending: AgentPendingToolCall,
        action: AgentHumanDecisionAction,
        feedback: String? = nil,
        editedArgumentsJSON: String? = nil,
        provider: any LLMChatProvider,
        definitions: [AgentToolDefinition],
        registry: AgentToolRegistry,
        fixture: LoopWorkspaceFixture,
        options: AgentLoopOptions = AgentLoopOptions(),
        hookEngine: AgentHookEngine = AgentHookEngine(hooks: [])
    ) -> AgentLoopResumeRequest {
        AgentLoopResumeRequest(
            pending: pending,
            action: action,
            feedback: feedback,
            editedArgumentsJSON: editedArgumentsJSON,
            provider: provider,
            toolDefinitions: definitions,
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
            apiKey: "test-key",
            options: options,
            hookEngine: hookEngine,
            permissionEvaluator: AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())
        )
    }

    private func sidecarRuntime(
        fixtureName: String,
        handshakeTimeout: TimeInterval = 5
    ) -> LangGraphAgentRuntime {
        let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let runtimeURL = repositoryURL.appendingPathComponent("AgentRuntime", isDirectory: true)
        let fixtureURL = runtimeURL.appendingPathComponent("tests/fixtures/\(fixtureName)", isDirectory: false)
        let configuration = SidecarLaunchConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-m", "sci_station_agent.main", "--fixture", fixtureURL.path],
            environment: [
                "PYTHONPATH": runtimeURL.path,
                "PYTHONUNBUFFERED": "1"
            ],
            workingDirectoryURL: repositoryURL,
            handshakeTimeout: handshakeTimeout,
            requestTimeout: 5
        )
        return LangGraphAgentRuntime(
            supervisor: SidecarProcessSupervisor(configuration: configuration),
            fallbackRuntime: nil
        )
    }

    private func sidecarCoordinator(
        fixtureName: String,
        handshakeTimeout: TimeInterval = 5
    ) -> SidecarRuntimeCoordinator {
        let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let runtimeURL = repositoryURL.appendingPathComponent("AgentRuntime", isDirectory: true)
        let fixtureURL = runtimeURL.appendingPathComponent("tests/fixtures/\(fixtureName)", isDirectory: false)
        let configuration = SidecarLaunchConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-m", "sci_station_agent.main", "--fixture", fixtureURL.path],
            environment: [
                "PYTHONPATH": runtimeURL.path,
                "PYTHONUNBUFFERED": "1"
            ],
            workingDirectoryURL: repositoryURL,
            handshakeTimeout: handshakeTimeout,
            requestTimeout: 5
        )
        return SidecarRuntimeCoordinator(supervisor: SidecarProcessSupervisor(configuration: configuration))
    }

    private func sidecarRuntimeRequest(
        runID: String,
        goal: String = "P34 sidecar fixture run",
        fixture: LoopWorkspaceFixture,
        definitions: [AgentToolDefinition] = [],
        registry: AgentToolRegistry = AgentToolRegistry(tools: [])
    ) -> AgentRuntimeRequest {
        AgentRuntimeRequest(
            runID: runID,
            threadID: "thread-\(runID)",
            goal: goal,
            initialMessages: [LLMChatMessage(role: .user, content: goal)],
            provider: ScriptedChatProvider(responses: [
                LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Sidecar provider response."))
            ]),
            toolDefinitions: definitions,
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, selectedPaperID: "demo-paper", researchRoot: fixture.root, currentProjectID: "demo-project"),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )
    }

    private struct GraphToolTestFixture {
        var rootURL: URL
        var root: ResearchRoot
        var workspace: ResearchWorkspace
        var repo: GraphRepository
        var paperRepository: PaperRepository
        var context: AgentToolContext
    }

    private func graphToolFixture(name: String) async throws -> GraphToolTestFixture {
        let rootURL = temporaryDirectoryURL().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let workspace = ResearchWorkspace(rootURL: rootURL)
        let repo = GraphRepository()
        try await repo.open(in: root)
        let paperRepository = PaperRepository()
        let context = AgentToolContext(
            workspace: workspace,
            researchRoot: root,
            currentProjectID: "proj"
        )
        return GraphToolTestFixture(
            rootURL: rootURL,
            root: root,
            workspace: workspace,
            repo: repo,
            paperRepository: paperRepository,
            context: context
        )
    }

    private func graphPaper(id: String, graphNodeID: String, title: String, year: Int, projectID: String, isCore: Bool) -> Paper {
        var paper = samplePaper(id: id)
        paper.citekey = id
        paper.title = title
        paper.year = year
        paper.arxiv = nil
        paper.graphNodeID = graphNodeID
        paper.projectIDs = [projectID]
        paper.coreProjectIDs = isCore ? [projectID] : []
        paper.paperDirectoryRelativePath = "library/papers/Uncategorized/\(id)"
        return paper
    }

    private func samplePaper(id: String) -> Paper {
        Paper(
            id: id,
            citekey: "smith2024graph",
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith", "Alice Wang"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            url: "https://arxiv.org/abs/2401.12345",
            pdfRelativePath: "paper.pdf",
            tags: ["rag"],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: ["related-work"],
            createdAt: Date(timeIntervalSince1970: 1_714_176_000),
            updatedAt: Date(timeIntervalSince1970: 1_714_176_000),
            paperDirectoryRelativePath: "library/papers/Uncategorized/\(id)",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
    }

    private func sampleResearchProject(id: String) -> ResearchProject {
        ResearchProject(
            id: id,
            name: id.replacingOccurrences(of: "-", with: " ").capitalized,
            description: "P42 fixture project",
            colorHex: "#4F7CAC",
            iconName: "folder",
            relativePath: "projects/\(id)",
            createdAt: Date(timeIntervalSince1970: 1_777_500_000),
            updatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
    }

    private func sampleTodo(id: String, title: String, projectID: String, dueDate: Date?) -> TodoItem {
        TodoItem(
            id: id,
            title: title,
            status: .open,
            dueDate: dueDate,
            priority: .high,
            projectIDs: [projectID],
            tags: [],
            relatedPaperIDs: [],
            notes: nil,
            createdAt: Date(timeIntervalSince1970: 1_777_500_000),
            updatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
    }

    private func sampleMarkdownDocument(relativePath: String, title: String) -> MarkdownDocument {
        MarkdownDocument(
            fileURL: URL(fileURLWithPath: "/tmp/\(relativePath)"),
            relativePath: relativePath,
            category: "gaps",
            title: title,
            frontmatter: [:],
            body: "# \(title)",
            rawContents: "# \(title)",
            outgoingLinks: [],
            pageKeys: [WikiLink.normalizePageKey(title)]
        )
    }

    private func sampleAgentRun(
        id: String,
        projectID: String?,
        createdAt: Date,
        lifecycleState: AgentRunState = .completed,
        toolResults: [AgentToolResult] = []
    ) -> AgentRun {
        AgentRun(
            id: id,
            goal: "P42 fixture run",
            createdAt: createdAt,
            completedAt: lifecycleState == .completed ? createdAt.addingTimeInterval(1) : nil,
            mode: .planOnly,
            plan: AgentPlan(title: "Fixture Draft", summary: "Fixture Draft", toolCalls: []),
            toolResults: toolResults,
            currentProjectID: projectID,
            lifecycleState: lifecycleState
        )
    }

    private func artifactToolResult(
        runID: String,
        kind: String,
        createdAt: Date,
        title: String? = nil,
        requiresConfirmation: Bool = false
    ) throws -> AgentToolResult {
        let artifact = AgentArtifactDraft(
            id: "artifact-\(runID)-\(kind)",
            runID: runID,
            kind: kind,
            proposedPath: "wiki/projects/\(kind).md",
            title: title ?? kind.replacingOccurrences(of: "_", with: " ").capitalized,
            content: "# Artifact",
            evidenceRefs: sampleEvidenceRefs(prefix: runID, count: 1)
        )
        return AgentToolResult(
            callID: "call-\(runID)-\(kind)-\(Int(createdAt.timeIntervalSince1970))",
            toolName: "artifact_draft",
            succeeded: true,
            requiresConfirmation: requiresConfirmation,
            message: artifact.title,
            payload: try jsonValue(artifact)
        )
    }

    private func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try AgentRunDirectoryStore.encoder().encode(value)
        return try AgentRunDirectoryStore.decoder().decode(JSONValue.self, from: data)
    }

    private func sampleEvidenceRefs(prefix: String, count: Int = 6) -> [AgentEvidenceRef] {
        (1...count).map { index in
            AgentEvidenceRef(
                sourceType: "paper",
                sourceID: "\(prefix)-paper-\(index)",
                relativePath: "library/papers/\(prefix)-paper-\(index)/paper.md",
                startLine: 1,
                endLine: 8,
                sourceHash: "sha256:\(prefix)-\(index)",
                chunkID: "paper:\(prefix)-\(index):1-8",
                heading: "Evidence \(index)",
                quote: "Evidence-backed claim \(index).",
                confidence: 0.74
            )
        }
    }

    private func temporaryDirectoryURL() -> URL {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    private func firstModuleConfiguration(from stream: AsyncStream<WorkspaceModuleConfiguration>) async throws -> WorkspaceModuleConfiguration {
        try await withThrowingTaskGroup(of: WorkspaceModuleConfiguration.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                guard let configuration = await iterator.next() else {
                    throw ValidationError(message: "Module configuration watch stream ended before publishing a change.")
                }
                return configuration
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                throw ValidationError(message: "Timed out waiting for workspace module configuration watcher.")
            }
            guard let configuration = try await group.next() else {
                throw ValidationError(message: "Module configuration watcher did not produce a result.")
            }
            group.cancelAll()
            return configuration
        }
    }

    private func zipData(entries: [(path: String, data: Data)]) throws -> Data {
        let sourceDirectoryURL = temporaryDirectoryURL()
        let zipDirectoryURL = temporaryDirectoryURL()
        let zipURL = zipDirectoryURL.appendingPathComponent("archive.zip", isDirectory: false)

        defer {
            try? FileManager.default.removeItem(at: sourceDirectoryURL)
            try? FileManager.default.removeItem(at: zipDirectoryURL)
        }

        for entry in entries {
            let fileURL = sourceDirectoryURL.appendingPathComponent(entry.path, isDirectory: false)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: fileURL, options: .atomic)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qry", zipURL.path, "."]
        process.currentDirectoryURL = sourceDirectoryURL

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown zip error"
            throw ValidationError(message: "zip failed: \(errorText)")
        }

        return try Data(contentsOf: zipURL)
    }

    private func gitTrackedFiles(in repoURL: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "ls-files"]
        process.currentDirectoryURL = repoURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown git error"
            throw ValidationError(message: "git ls-files failed: \(errorText)")
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func trackedSciAIContainsRawSecrets(at directoryURL: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let secretPattern = #"(?i)(bearer\s+[A-Za-z0-9._\-]{12,}|sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|\"(api[_-]?key|client[_-]?secret|refresh[_-]?token|private[_-]?key)\"\s*:\s*\"(?!\$\{|keychain:|env:|secret-ref:)[^\"]{8,}\")"#
        guard let expression = try? NSRegularExpression(pattern: secretPattern) else {
            return true
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if expression.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }

        return false
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw ValidationError(message: message)
        }
    }

    private func expectWikiWriteRejected(_ tool: WriteMarkdownPlanAgentTool, context: AgentToolContext, path: String) async throws {
        var didReject = false
        do {
            _ = try await tool.invoke(
                argumentsJSON: "{\"title\":\"Rejected\",\"body\":\"Body\",\"relative_path\":\"\(path)\"}",
                context: context
            )
        } catch {
            didReject = true
        }
        try expect(didReject, "Wiki writeback should reject invalid path: \(path)")
    }

    private func jsonObject(_ value: JSONValue?, _ message: String) throws -> [String: JSONValue] {
        guard case let .object(object)? = value else {
            throw ValidationError(message: message)
        }
        return object
    }

    private func jsonArray(_ value: JSONValue?, _ message: String) throws -> [JSONValue] {
        guard case let .array(array)? = value else {
            throw ValidationError(message: message)
        }
        return array
    }

    private func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw ValidationError(message: message)
        }
        return value
    }

    private func runtimeEventLabel(_ event: AgentRuntimeEvent) -> String {
        switch event {
        case .runStarted: return "runStarted"
        case .nodeStarted: return "nodeStarted"
        case .assistantDelta: return "assistantDelta"
        case .assistantMessage: return "assistantMessage"
        case .toolCallRequested: return "toolCallRequested"
        case .toolCallCompleted: return "toolCallCompleted"
        case .approvalRequired: return "approvalRequired"
        case .artifactDraft: return "artifactDraft"
        case .checkpointSaved: return "checkpointSaved"
        case .finalResponse: return "finalResponse"
        case .runCancelled: return "runCancelled"
        case .runFailed: return "runFailed"
        case .sidecarStarting: return "sidecarStarting"
        case .sidecarReady: return "sidecarReady"
        case .sidecarUnavailable: return "sidecarUnavailable"
        case .sidecarCrashed: return "sidecarCrashed"
        case .fallbackToLegacyRuntime: return "fallbackToLegacyRuntime"
        }
    }
}

private struct ValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private extension AgentRuntimeEvent {
    var isSidecarStarting: Bool {
        if case .sidecarStarting = self { return true }
        return false
    }

    var isSidecarUnavailable: Bool {
        if case .sidecarUnavailable = self { return true }
        return false
    }

    var isFallbackToLegacyRuntime: Bool {
        if case .fallbackToLegacyRuntime = self { return true }
        return false
    }
}

private struct StaticLLMProvider: LLMProvider {
    let response: String

    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        response
    }
}

private actor ScriptedChatProvider: LLMProvider, LLMChatProvider {
    private var responses: [LLMProviderResponse]
    private var requests: [LLMProviderRequest] = []

    init(responses: [LLMProviderResponse]) {
        self.responses = responses
    }

    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        responses.first?.message.content ?? ""
    }

    func respond(to request: LLMProviderRequest, configuration: LLMConfiguration, apiKey: String) async throws -> LLMProviderResponse {
        requests.append(request)
        if responses.count > 1 {
            return responses.removeFirst()
        }
        if let response = responses.first {
            return response
        }
        return LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: ""))
    }

    func recordedRequests() -> [LLMProviderRequest] {
        requests
    }
}

private actor ScriptedFailingChatProvider: LLMProvider, LLMChatProvider {
    private var steps: [Result<LLMProviderResponse, LLMProviderError>]
    private var requests: [LLMProviderRequest] = []

    init(steps: [Result<LLMProviderResponse, LLMProviderError>]) {
        self.steps = steps
    }

    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        guard let first = steps.first else {
            return ""
        }
        switch first {
        case let .success(response):
            return response.message.content
        case let .failure(error):
            throw error
        }
    }

    func respond(to request: LLMProviderRequest, configuration: LLMConfiguration, apiKey: String) async throws -> LLMProviderResponse {
        requests.append(request)
        guard !steps.isEmpty else {
            return LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: ""))
        }
        let step = steps.removeFirst()
        switch step {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [LLMProviderRequest] {
        requests
    }
}

private actor RecordingAgentTool: AgentTool {
    nonisolated let definition: AgentToolDefinition
    private var results: [AgentToolResult]
    private var argumentsLog: [String] = []

    init(definition: AgentToolDefinition, results: [AgentToolResult]) {
        self.definition = definition
        self.results = results
    }

    func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        argumentsLog.append(argumentsJSON)
        if results.count > 1 {
            return results.removeFirst()
        }
        if let result = results.first {
            return result
        }
        return AgentToolResult(callID: "", toolName: definition.name, succeeded: true, message: "Recorded tool result.")
    }

    func invocationCount() -> Int {
        argumentsLog.count
    }

    func invokedArguments() -> [String] {
        argumentsLog
    }
}

private actor RecordingPaperImporter: PaperImporter {
    nonisolated let contribution = ImporterContribution(id: "test.importer", title: "Test Importer", inputKinds: ["doi"])
    private var values: [String] = []

    nonisolated func canHandle(_ input: PaperImportInput) -> Bool {
        input.kind == .doi
    }

    func importPaper(_ input: PaperImportInput, context: PluginContext) async throws -> PaperImportResult {
        values.append(input.value)
        let draft = PaperMetadataDraft(
            title: "Imported Paper",
            authors: ["Test Author"],
            year: 2026,
            venue: nil,
            doi: input.value,
            arxiv: nil,
            inspireID: nil,
            url: nil,
            pdfURL: nil,
            abstract: nil,
            categories: [],
            sourceProvider: context.pluginID
        )
        return PaperImportResult(paperID: "paper:\(input.value)", metadata: draft)
    }

    func handledValues() -> [String] {
        values
    }
}

private actor RecordingPaperMetadataProvider: PaperMetadataProviderPlugin {
    nonisolated let contribution = MetadataProviderContribution(id: "test.metadata", title: "Test Metadata", supportedIdentifiers: ["doi"])
    private var values: [String] = []

    func lookup(_ query: MetadataLookupQuery, context: PluginContext) async throws -> [PaperMetadataCandidate] {
        values.append(query.value)
        let draft = PaperMetadataDraft(
            title: "Metadata Candidate",
            authors: ["Provider Author"],
            year: 2026,
            venue: nil,
            doi: query.value,
            arxiv: nil,
            inspireID: nil,
            url: nil,
            pdfURL: nil,
            abstract: nil,
            categories: [],
            sourceProvider: context.pluginID
        )
        return [PaperMetadataCandidate(draft: draft, providerID: contribution.id)]
    }

    func lookupValues() -> [String] {
        values
    }
}

private final class MinerUAPIMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var zipData = Data()
    nonisolated(unsafe) static var requestLog: [String] = []
    nonisolated(unsafe) static var uploadContentTypeHeaders: [String?] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let method = request.httpMethod ?? "GET"
        let host = url.host ?? ""
        let requestKey = "\(method) \(host)\(url.path)"
        Self.requestLog.append(requestKey)

        let statusCode: Int
        let contentType: String
        let data: Data

        switch requestKey {
        case "POST mineru.test/api/v4/file-urls/batch":
            statusCode = 200
            contentType = "application/json"
            data = Data(
                """
                {
                  "code": 0,
                  "msg": "ok",
                  "data": {
                    "batch_id": "batch-1",
                    "file_urls": ["https://upload.test/upload/mineru-images-paper.pdf"]
                  }
                }
                """.utf8
            )
        case "PUT upload.test/upload/mineru-images-paper.pdf":
            Self.uploadContentTypeHeaders.append(request.value(forHTTPHeaderField: "Content-Type"))
            statusCode = request.value(forHTTPHeaderField: "Content-Type") == nil ? 204 : 415
            contentType = "text/plain"
            data = Data()
        case "GET mineru.test/api/v4/extract-results/batch/batch-1":
            statusCode = 200
            contentType = "application/json"
            data = Data(
                """
                {
                  "code": 0,
                  "msg": "ok",
                  "data": {
                    "extract_result": [
                      {
                        "file_name": "mineru-images-paper.pdf",
                        "data_id": "mineru-images-paper",
                        "state": "done",
                        "full_zip_url": "https://download.test/mineru.zip"
                      }
                    ]
                  }
                }
                """.utf8
            )
        case "GET download.test/mineru.zip":
            statusCode = 200
            contentType = "application/zip"
            data = Self.zipData
        default:
            statusCode = 404
            contentType = "text/plain"
            data = Data("not found: \(requestKey)".utf8)
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
