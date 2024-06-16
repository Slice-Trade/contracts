// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/console.sol";

import {MessagingFee} from "@lz-oapp-v2/OApp.sol";
import {ILayerZeroEndpointV2, MessagingParams} from "@lz-oapp-v2/interfaces/ILayerZeroEndpointV2.sol";

import {IChainInfo} from "../interfaces/IChainInfo.sol";
import {CrossChainData} from "../libs/CrossChainData.sol";
import {SliceCore} from "../SliceCore.sol";
import {ISliceToken} from "../SliceToken.sol";
import "../Structs.sol";

contract LZFeeEstimator {
    IChainInfo public immutable chainInfo;
    SliceCore public immutable sliceCore;
    ILayerZeroEndpointV2 public immutable endpoint;

    constructor(SliceCore _sliceCore, IChainInfo _chainInfo, ILayerZeroEndpointV2 _endpoint) {
        sliceCore = _sliceCore;
        chainInfo = _chainInfo;
        endpoint = _endpoint;
    }

    struct KeepingTrack {
        uint256 currentCount;
        uint256 currentChainId;
        uint8 totalMsgCount;
    }

    function estimateLzFee(address token, CrossChainSignalType ccsType, uint128[] calldata replyMsgValues)
        external
        view
        returns (uint256[] memory)
    {
        // get the positions
        Position[] memory positions = ISliceToken(token).getPositions();

        CrossChainSignal[] memory ccMsgs = new CrossChainSignal[](positions.length);

        KeepingTrack memory kt = KeepingTrack(0, 0, 0);

        uint256[] memory fees = new uint256[](replyMsgValues.length);

        for (uint256 i = 0; i < positions.length; i++) {
            if (isPositionLocal(positions[i])) {
                continue;
            } else {
                uint256 fee;

                (ccMsgs, kt, fee) =
                    groupAndQuoteLzMsg(ccMsgs, i, positions.length, ccsType, positions[i], kt, replyMsgValues);
                if (fee != 0) {
                    fees[kt.totalMsgCount - 1] = fee;
                }
            }
        }

        return fees;
    }

    function createCcs(CrossChainSignalType ccsType, address token, uint256 value) internal view returns (CrossChainSignal memory) {
        return CrossChainSignal({
            id: bytes32(0),
            srcChainId: uint32(block.chainid),
            ccsType: ccsType,
            success: true,
            user: msg.sender,
            underlying: token,
            units: type(uint256).max,
            value: value
        });
    }

    function estimateLzFeeCompleted(Position[] memory positions, CrossChainSignalType ccsType, uint32 chainId)
        external
        view
        returns (uint256 feeTotal)
    {
        CrossChainSignal[] memory ccMsgs = new CrossChainSignal[](positions.length);
        uint256 currentCount;

        for (uint256 i = 0; i < positions.length; i++) {
            if (isPositionLocal(positions[i])) {
                CrossChainSignal memory ccs = CrossChainSignal({
                    id: bytes32(0),
                    srcChainId: chainId,
                    ccsType: ccsType,
                    success: true,
                    user: msg.sender,
                    underlying: positions[i].token,
                    units: type(uint256).max,
                    value: 0
                });

                ccMsgs[currentCount] = ccs;
                ++currentCount;
            } else {
                continue;
            }
        }

        assembly {
            mstore(ccMsgs, currentCount)
        }

        bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);

        Chain memory dstChain = chainInfo.getChainInfo(chainId);

        bytes memory _lzSendOpts = CrossChainData.createLzSendOpts({_gas: sliceCore.lzGasLookup(ccsType), _value: 0});

        MessagingFee memory _fee = endpoint.quote(
            MessagingParams(
                dstChain.lzEndpointId, bytes32(uint256(uint160(address(sliceCore)))), ccsMsgsEncoded, _lzSendOpts, false
            ),
            address(sliceCore)
        );
        console.log(_fee.nativeFee);
        feeTotal = _fee.nativeFee;
    }

    function isPositionLocal(Position memory position) internal view returns (bool) {
        return position.chainId == block.chainid;
    }

    function groupAndQuoteLzMsg(
        CrossChainSignal[] memory ccMsgs,
        uint256 currentIdx,
        uint256 positionsLength,
        CrossChainSignalType ccsType,
        Position memory position,
        KeepingTrack memory kt,
        uint128[] memory replyMsgVal
    ) internal view returns (CrossChainSignal[] memory, KeepingTrack memory, uint256 feeSum) {
        MessagingFee memory _fee;
        if (kt.currentChainId == position.chainId) {
            // this means we're at antoher element with the same chain
            ccMsgs[kt.currentCount] = createCcs(ccsType, position.token,0);
            ++kt.currentCount;
        } else {
            if (kt.currentChainId != 0) {
                // this means we're at a new chain, so send the previous chains msgs
                {
                    uint256 currCount = kt.currentCount;
                    assembly {
                        mstore(ccMsgs, currCount)
                    }
                }
                bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);

                Chain memory dstChain = chainInfo.getChainInfo(kt.currentChainId);

                bytes memory _lzSendOpts = CrossChainData.createLzSendOpts({
                    _gas: sliceCore.lzGasLookup(ccsType),
                    _value: replyMsgVal[kt.totalMsgCount]
                });

                _fee = endpoint.quote(
                    MessagingParams(
                        dstChain.lzEndpointId,
                        bytes32(uint256(uint160(address(sliceCore)))),
                        ccsMsgsEncoded,
                        _lzSendOpts,
                        false
                    ),
                    address(sliceCore)
                );
                feeSum += _fee.nativeFee;
                ++kt.totalMsgCount;
                kt.currentCount = 0;
                kt.currentChainId = position.chainId;
                ccMsgs = new CrossChainSignal[](positionsLength);
            }

            ccMsgs[kt.currentCount] = createCcs(ccsType, position.token, replyMsgVal[kt.totalMsgCount]);
            kt.currentChainId = position.chainId;
            ++kt.currentCount;
        }
        // if it is the last message and we have a chainId in the array we send the message
        if (currentIdx == positionsLength - 1 && kt.currentCount != 0) {
            // this means we reached the end of the list and have a non empty array
            {
                uint256 currCount = kt.currentCount;
                assembly {
                    mstore(ccMsgs, currCount)
                }
            }
            bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);
            Chain memory dstChain = chainInfo.getChainInfo(kt.currentChainId);

            bytes memory _lzSendOpts = CrossChainData.createLzSendOpts({
                _gas: sliceCore.lzGasLookup(ccsType),
                _value: replyMsgVal[kt.totalMsgCount]
            });

            _fee = endpoint.quote(
                MessagingParams(
                    dstChain.lzEndpointId,
                    bytes32(uint256(uint160(address(sliceCore)))),
                    ccsMsgsEncoded,
                    _lzSendOpts,
                    false
                ),
                address(this)
            );
            feeSum += _fee.nativeFee;
            ++kt.totalMsgCount;
        }

        return (ccMsgs, kt, feeSum);
    }
}
