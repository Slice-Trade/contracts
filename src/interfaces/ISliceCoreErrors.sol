// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ISliceCoreErrors {
    error UnauthorizedCaller();
    
    error TokenCreationDisabled();

    error UnregisteredSliceToken();

    error MintIdDoesNotExist();

    error RedeemIdDoesNotExist();

    error OriginNotSliceCore();

    error InvalidTransactionState();

    error NotAllCrossChainSignalsReceived();
}
