// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Forked from Universe Auction House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

interface IRandomNumberGenerator {
    function initVRF(address _contractAddress) external;
    function getWinners(uint256 raffleId) external;
    function getWinnersMock(uint256 raffleId) external;
}