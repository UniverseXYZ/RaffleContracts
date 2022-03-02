// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Forked from Universe Raffle House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

import "./IRoyaltiesProvider.sol";
import "../UniversalRaffleCore.sol";

/// @title Users buy raffle tickets in order to win deposited ERC721 tokens.
/// @notice This interface should be implemented by the NFTRaffle contract
/// @dev This interface should be implemented by the NFTRaffle contract
interface IUniversalRaffle {
  /// @notice Create a raffle with initial parameters
  /// @param config Raffle configuration
  /// @dev config.raffler Raffler creator (msg.sender)
  /// @dev config.ERC20PurchaseToken ERC20 token used to purchase raffle tickets
  /// @dev config.startTime The start of the raffle
  /// @dev config.endTime End of the raffle
  /// @dev config.maxTicketCount Maximum tickets allowed to be sold
  /// @dev config.minTicketCount Minimum tickets that must be sold for raffle to proceed
  /// @dev config.ticketPrice Price per raffle ticket
  /// @dev config.totalSlots The number of winner slots which the raffle will have
  /// @dev config.paymentSplits Array of payment splits which will be distributed after raffle ends
  function createRaffle(UniversalRaffleCore.RaffleConfig calldata config) external returns (uint256);

  /// @notice Change raffle configuration
  /// @param config Raffle configuration above
  function reconfigureRaffle(UniversalRaffleCore.RaffleConfig calldata config, uint256 existingRaffleId) external returns (uint256);

  /// @notice Deposit ERC721 assets to the specified Raffle
  /// @param raffleId The raffle id
  /// @param slotIndices Array of slot indexes
  /// @param tokens Array of ERC721 arrays
  function batchDepositToRaffle(
      uint256 raffleId,
      uint256[] calldata slotIndices,
      UniversalRaffleCore.NFT[][] calldata tokens
  ) external;

  /// @notice Deposit ERC721 assets to the specified Raffle
  /// @param raffleId The raffle id
  /// @param slotIndex Index of the slot
  /// @param tokens Array of ERC721 objects
  function depositERC721(
      uint256 raffleId,
      uint256 slotIndex,
      UniversalRaffleCore.NFT[] calldata tokens
  ) external returns (uint256[] memory);

  /// @notice Withdraws the deposited ERC721 before an auction has started
  /// @param raffleId The raffle id
  /// @param slotIndex The slot index
  /// @param amount The amount which should be withdrawn
  function withdrawDepositedERC721(
      uint256 raffleId,
      uint256 slotIndex,
      uint256 amount
  ) external;

  /// @notice Purchases raffle tickets
  /// @param raffleId The raffle id
  /// @param amount The amount of raffle tickets
  function buyRaffleTicket(uint256 raffleId, uint256 amount) external payable;

  /// @notice Select winners of raffle
  /// @param raffleId The raffle id
  function finalizeRaffle(uint256 raffleId) external;

  /// @notice Select winners of raffle
  /// @param raffleId The raffle id
  /// @param winners Array of winner addresses
  function setWinners(uint256 raffleId, address[] memory winners) external;

  /// @notice Claims and distributes the NFTs from a winning slot
  /// @param raffleId The auction id
  /// @param slotIndex The slot index
  /// @param amount The amount which should be withdrawn
  function claimERC721Rewards(
      uint256 raffleId,
      uint256 slotIndex,
      uint256 amount
  ) external;

  /// @notice Refunds purchase amount for raffle tickets
  /// @param raffleId The raffle id
  /// @param tokenIds The ids of ticket NFTs bought from raffle
  function refundRaffleTickets(uint256 raffleId, uint256[] memory tokenIds) external;

  /// @notice Cancels an auction which has not started yet
  /// @param raffleId The raffle id
  function cancelRaffle(uint256 raffleId) external;

  /// @notice Sets maximum number of tickets someone can buy in one bulk purchase
  /// @param maxBulkPurchaseCount The bulk count
  function setMaxBulkPurchaseCount(uint256 maxBulkPurchaseCount) external returns(uint256);

  /// @notice Sets the NFT slot limit for raffle
  /// @param nftSlotLimit The royalty percentage
  function setNftSlotLimit(uint256 nftSlotLimit) external returns(uint256);

  /// @notice Sets the percentage of the royalty which wil be kept from each sale
  /// @param royaltyFeeBps The royalty percentage in Basis points (1000 - 10%)
  function setRoyaltyFeeBps(uint256 royaltyFeeBps) external returns(uint256);

  /// @notice Sets the RoyaltiesRegistry
  /// @param royaltiesRegistry The royalties registry address
  function setRoyaltiesRegistry(IRoyaltiesProvider royaltiesRegistry) external returns (IRoyaltiesProvider);

  /// @notice Modifies whether a token is supported for bidding
  /// @param erc20token The erc20 token
  /// @param value True or false
  function setSupportedERC20Tokens(address erc20token, bool value) external returns (address, bool);

  /// @notice Gets raffle information
  /// @param raffleId The raffle id
  function getRaffleInfo(uint256 raffleId)
      external
      view
      returns (UniversalRaffleCore.RaffleConfig memory, uint256);

  /// @notice Gets deposited erc721s for slot
  /// @param raffleId The raffle id
  /// @param slotIndex The slot index
  function getDepositedNftsInSlot(uint256 raffleId, uint256 slotIndex)
      external
      view
      returns (UniversalRaffleCore.DepositedNFT[] memory);

  /// @notice Gets slot winner for particular auction
  /// @param raffleId The raffle id
  /// @param slotIndex The slot index
  function getSlotWinner(uint256 raffleId, uint256 slotIndex) external view returns (address);

  /// @notice Gets slot info for particular auction
  /// @param raffleId The raffle id
  /// @param slotIndex The slot index
  function getSlotInfo(uint256 raffleId, uint256 slotIndex) external view returns (UniversalRaffleCore.SlotInfo memory);

}