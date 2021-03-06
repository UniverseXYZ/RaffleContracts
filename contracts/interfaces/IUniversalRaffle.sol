// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Adapted from Universe Raffle House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

import "./IRoyaltiesProvider.sol";
import "../UniversalRaffleCore.sol";
import "../UniversalRaffleCoreTwo.sol";
import "../UniversalRaffleSchema.sol";

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
  function createRaffle(UniversalRaffleSchema.RaffleConfig calldata config) external returns (uint256);

  /// @notice Change raffle configuration
  /// @param config Raffle configuration above
  /// @param existingRaffleId The raffle id
  function reconfigureRaffle(UniversalRaffleSchema.RaffleConfig calldata config, uint256 existingRaffleId) external returns (uint256);

  /// @notice Sets addresses able to deposit NFTs to raffle
  /// @param raffleId The raffle id
  /// @param allowList Array of [address, 1 for true, 0 for false]
  function setDepositors(uint256 raffleId, UniversalRaffleSchema.AllowList[] calldata allowList) external;

  /// @notice Sets allow list addresses and allowances
  /// @param raffleId The raffle id
  /// @param allowList Array of [address, allowance]
  function setAllowList(uint256 raffleId, UniversalRaffleSchema.AllowList[] calldata allowList) external;

  /// @notice Turns allow list on and off
  /// @param raffleId The raffle id
  function toggleAllowList(uint256 raffleId) external;

  /// @notice Deposit ERC721 assets to the specified Raffle
  /// @param raffleId The raffle id
  /// @param slotIndices Array of slot indexes
  /// @param tokens Array of ERC721 arrays
  function depositNFTsToRaffle(
      uint256 raffleId,
      uint256[] calldata slotIndices,
      UniversalRaffleSchema.NFT[][] calldata tokens
  ) external;

  /// @notice Withdraws the deposited ERC721 before an auction has started
  /// @param raffleId The raffle id
  /// @param slotNftIndexes The slot index and nft index in array [[slot index, nft index]]
  function withdrawDepositedERC721(
      uint256 raffleId,
      UniversalRaffleSchema.SlotIndexAndNFTIndex[] calldata slotNftIndexes
  ) external;

  /// @notice Purchases raffle tickets
  /// @param raffleId The raffle id
  /// @param amount The amount of raffle tickets
  function buyRaffleTickets(uint256 raffleId, uint256 amount) external payable;

  /// @notice Select winners of raffle
  /// @param raffleId The raffle id
  function finalizeRaffle(uint256 raffleId, bytes32 keyHash, uint64 subscriptionId, uint16 minConf, uint32 callbackGas) external;

  /// @notice Select winners of raffle
  /// @param raffleId The raffle id
  function setWinners(uint256 raffleId, uint256[] memory winnerIds) external;

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

  /// @notice Withdraws the captured revenue from the auction to the auction owner. Can be called multiple times after captureSlotRevenue has been called.
  /// @param raffleId The auction id
  function distributeCapturedRaffleRevenue(uint256 raffleId) external;


  /// @notice Gets the minimum reserve price for auciton slot
  /// @param raffleId The raffle id
  /// @param slotIndex The slot index
  /// @param nftSlotIndex The nft slot index
  function distributeSecondarySaleFees(
      uint256 raffleId,
      uint256 slotIndex,
      uint256 nftSlotIndex
  ) external;

  /// @notice Withdraws the aggregated royalites amount of specific token to a specified address
  /// @param token The address of the token to withdraw
  function distributeRoyalties(address token) external returns(uint256);

  /// @notice Sets a raffle config value
  /// @param value The value of the configuration
  /// configType value 0: maxBulkPurchaseCount - Sets maximum number of tickets someone can buy in one bulk purchase
  /// configType value 1: Sets the NFT slot limit for raffle
  /// configType value 2: Sets the percentage of the royalty which wil be kept from each sale in basis points (1000 - 10%)
  function setRaffleConfigValue(uint256 configType, uint256 value) external returns(uint256);

  /// @notice Sets the RoyaltiesRegistry
  /// @param royaltiesRegistry The royalties registry address
  function setRoyaltiesRegistry(IRoyaltiesProvider royaltiesRegistry) external returns (IRoyaltiesProvider);

  /// @notice Modifies whether a token is supported for bidding
  /// @param erc20token The erc20 token
  /// @param value True or false
  function setSupportedERC20Tokens(address erc20token, bool value) external returns (address, bool);

  /// @notice Gets raffle state
  /// @param raffleId The raffle id
  function getRaffleState(uint256 raffleId)
      external
      view
      returns (UniversalRaffleSchema.RaffleConfig memory, UniversalRaffleSchema.RaffleState memory);

  /// @notice Gets raffle finalize state variables
  /// @param raffleId The raffle id
  function getRaffleFinalize(uint256 raffleId)
      external
      view
      returns (bool, uint256, uint256);

  /// @notice Gets allow list
  /// @param raffleId The raffle id
  function getDepositorList(uint256 raffleId, address participant)
      external
      view
      returns (bool);


  /// @notice Gets allow list
  /// @param raffleId The raffle id
  function getAllowList(uint256 raffleId, address participant)
      external
      view
      returns (uint256);


  /// @notice Gets deposited erc721s for slot
  /// @param raffleId The raffle id
  /// @param slotIndex The slot index
  function getDepositedNftsInSlot(uint256 raffleId, uint256 slotIndex)
      external
      view
      returns (UniversalRaffleSchema.DepositedNFT[] memory);

  /// @notice Gets slot info for particular auction
  /// @param raffleId The raffle id
  /// @param slotIndex The slot index
  function getSlotInfo(uint256 raffleId, uint256 slotIndex) external view returns (UniversalRaffleSchema.SlotInfo memory);

  /// @notice Gets contract configuration controlled by DAO
  function getContractConfig() external view returns (UniversalRaffleSchema.ContractConfigByDAO memory);
}