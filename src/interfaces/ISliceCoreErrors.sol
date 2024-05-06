// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ISliceCoreErrors {
    error UnauthorizedCaller();
    error TokenCreationDisabled();

    error UnregisteredSliceToken();

    error TokenPriceNotTransferred();

    error MintIdDoesNotExist();
    error RedeemIdDoesNotExist();

    error LocalSwapFailed();

    error UnderlyingAssetTransferFailed();

    error OnlyStargateAdapterCanCall();

    error IncorrectAmountOut();

    error OnlyLzEndpointCanCall();

    error OriginNotSliceCore();

    error CrossChainSwapFailed();

    error CrossChainRedeemFailed();

    error LayerZeroSendFailed();

    error LocalAssetTransferFailed();
}
