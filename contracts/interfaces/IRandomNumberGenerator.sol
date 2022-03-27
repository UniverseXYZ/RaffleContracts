// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Adapted from Universe Auction House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

interface IRandomNumberGenerator {
    function initVRF(address _contractAddress) external;
    function getWinners(uint256 raffleId, bytes32 _keyHash, uint64 _subscriptionId, uint16 _minConf, uint32 _callbackGas) external;
    function getWinnersMock(uint256 raffleId) external;
}