//
//  Remove Tap.swift
//  Cork
//
//  Created by David Bureš on 03.09.2023.
//

import Foundation
import SwiftUI
import CorkShared

enum UntapError: LocalizedError
{
    case couldNotUntap(tapName: String, failureReason: String)

    var errorDescription: String?
    {
        switch self
        {
        case .couldNotUntap(let tapName, let failureReason):
            return String(localized: "error.tap.untap.could-not-untap.tap-\(tapName).failure-reason-\(failureReason)")
        }
    }
}

@MainActor
func removeTap(name: String, availableTaps: AvailableTaps, appState: AppState, shouldApplyUninstallSpinnerToRelevantItemInSidebar: Bool = false) async throws
{
    var indexToReplaceGlobal: Int?

    /// Store the old navigation selection to see if it got updated in the middle of switching
    let oldNavigationSelectionID: UUID? = appState.navigationSelection.wrappedValue

    if shouldApplyUninstallSpinnerToRelevantItemInSidebar
    {
        if let indexToReplace = availableTaps.addedTaps.firstIndex(where: { $0.name == name })
        {
            availableTaps.addedTaps[indexToReplace].changeBeingModifiedStatus()

            indexToReplaceGlobal = indexToReplace
        }
    }
    else
    {
        appState.isShowingUninstallationProgressView = true
    }

    let untapResult: String = await shell(AppConstants.brewExecutablePath, ["untap", name]).standardError
    AppConstants.logger.debug("Untapping result: \(untapResult)")

    defer
    {
        appState.isShowingUninstallationProgressView = false
    }

    if untapResult.contains("Untapped")
    {
        AppConstants.logger.info("Untapping was successful")
        DispatchQueue.main.async
        {
            withAnimation
            {
                availableTaps.addedTaps.removeAll(where: { $0.name == name })
            }
        }

        if appState.navigationSelection != nil
        {
            /// Switch to the status page only if the user didn't open another details window in the middle of the tap removal process
            if oldNavigationSelectionID == appState.navigationSelection.wrappedValue
            {
                appState.navigationSelection.wrappedValue = nil
            }
        }
    }
    else
    {
        AppConstants.logger.warning("Untapping failed")

        if untapResult.contains("because it contains the following installed formulae or casks")
        {
            appState.showAlert(errorToShow: .couldNotRemoveTapDueToPackagesFromItStillBeingInstalled(offendingTapProhibitingRemovalOfTap: name))
        }

        if let indexToReplaceGlobal
        {
            availableTaps.addedTaps[indexToReplaceGlobal].changeBeingModifiedStatus()
        }
        else
        {
            AppConstants.logger.warning("Could not get index for that tap. Will loop over all of them")
            
            for index in availableTaps.addedTaps.indices
            {
                if availableTaps.addedTaps[index].isBeingModified
                {
                    availableTaps.addedTaps[index].isBeingModified = false
                }
            }
        }

        throw UntapError.couldNotUntap(tapName: name, failureReason: untapResult)
    }
}
