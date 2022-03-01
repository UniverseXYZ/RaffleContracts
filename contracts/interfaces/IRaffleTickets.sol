// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Product by universe.xyz

pragma solidity 0.8.11;


interface IRaffleTickets {
  function initRaffleTickets(address _contractAddress) external;
  function mint(address to, uint256 amount, uint256 raffleId) external;
  function totalSupply() external view returns (uint256);
  function raffleTicketCounter(uint256 raffleId) external view returns (uint256);
}