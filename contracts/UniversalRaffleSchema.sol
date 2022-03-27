// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Adapted from Universe Auction House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

import "./interfaces/IRoyaltiesProvider.sol";

library UniversalRaffleSchema {
    struct RaffleConfig {
        address raffler;
        address ERC20PurchaseToken;
        uint64 startTime;
        uint64 endTime;
        uint32 maxTicketCount;
        uint32 minTicketCount;
        uint32 totalSlots;
        uint256 ticketPrice;
        string raffleName;
        string ticketColorOne;
        string ticketColorTwo;
        PaymentSplit[] paymentSplits;
    }

    struct Raffle {
        uint32 ticketCounter;
        uint16 depositedNFTCounter;
        uint16 withdrawnNFTCounter;
        uint16 depositorCount;
        mapping(uint256 => Slot) slots;
        mapping(uint256 => bool) refunds;
        mapping(address => uint256) allowList;
        mapping(address => bool) depositors;
        bool useAllowList;
        bool isSetup;
        bool isCanceled;
        bool isFinalized;
        bool revenuePaid;
    }

    struct RaffleState {
        uint32 ticketCounter;
        uint16 depositedNFTCounter;
        uint16 withdrawnNFTCounter;
        bool useAllowList;
        bool isSetup;
        bool isCanceled;
        bool isFinalized;
        bool revenuePaid;
    }

    struct Slot {
        uint16 depositedNFTCounter;
        uint16 withdrawnNFTCounter;
        address winner;
        uint256 winnerId;
        mapping(uint256 => DepositedNFT) depositedNFTs;
    }

    struct SlotInfo {
        uint16 depositedNFTCounter;
        uint16 withdrawnNFTCounter;
        address winner;
        uint256 winnerId;
    }

    struct SlotIndexAndNFTIndex {
        uint16 slotIndex;
        uint16 NFTIndex;
    }

    struct NFT {
        uint256 tokenId;
        address tokenAddress;
    }

    struct DepositedNFT {
        address tokenAddress;
        uint256 tokenId;
        address depositor;
        bool hasSecondarySaleFees;
        bool feesPaid;
        address[] feesAddress;
        uint96[] feesValue;
    }

    struct PaymentSplit {
        address payable recipient;
        uint96 value;
    }

    struct AllowList {
        address participant;
        uint32 allocation;
    }

    struct ContractConfigByDAO {
        address daoAddress;
        address raffleTicketAddress;
        address vrfAddress;
        uint32 totalRaffles;
        uint32 maxNumberOfSlotsPerRaffle;
        uint32 maxBulkPurchaseCount;
        uint32 nftSlotLimit;
        uint32 royaltyFeeBps;
        bool daoInitialized;
    }

    struct Storage {
        bool unsafeVRFtesting;
        address vrfAddress;
        address raffleTicketAddress;

        address payable daoAddress;
        bool daoInitialized;

        // DAO Configurable Settings
        uint32 maxNumberOfSlotsPerRaffle;
        uint32 maxBulkPurchaseCount;
        uint32 royaltyFeeBps;
        uint32 nftSlotLimit;
        IRoyaltiesProvider royaltiesRegistry;
        mapping(address => bool) supportedERC20Tokens;

        // Raffle state and data storage
        uint32 totalRaffles;
        mapping(uint256 => RaffleConfig) raffleConfigs;
        mapping(uint256 => Raffle) raffles;
        mapping(uint256 => uint256) raffleRevenue;
        mapping(uint256 => uint256) rafflesDAOPool;
        mapping(uint256 => uint256) rafflesRoyaltyPool;
        mapping(address => uint256) royaltiesReserve;
    }


    event LogERC721Deposit(
        address indexed depositor,
        address tokenAddress,
        uint256 tokenId,
        uint256 indexed raffleId,
        uint256 slotIndex,
        uint256 nftSlotIndex
    );

    event LogERC721Withdrawal(
        address indexed depositor,
        address tokenAddress,
        uint256 tokenId,
        uint256 indexed raffleId,
        uint256 slotIndex,
        uint256 nftSlotIndex
    );

    event LogRaffleCreated(
        uint256 indexed raffleId,
        address indexed raffleOwner,
        string raffleName
    );

    event LogRaffleEdited(
        uint256 indexed raffleId,
        address indexed raffleOwner,
        string raffleName
    );

    event LogRaffleTicketsPurchased(
        address indexed purchaser,
        uint256 amount,
        uint256 indexed raffleId
    );

    event LogRaffleTicketsRefunded(
        address indexed purchaser,
        uint256 indexed raffleId
    );

    event LogERC721RewardsClaim(address indexed claimer, uint256 indexed raffleId, uint256 slotIndex, uint256 amount);

    event LogRaffleCanceled(uint256 indexed raffleId);

    event LogRaffleRevenueWithdrawal(address indexed recipient, uint256 indexed raffleId, uint256 amount);

    event LogRaffleSecondaryFeesPayout(uint256 indexed raffleId, uint256 slotIndex, uint256 nftSlotIndex);

    event LogRoyaltiesWithdrawal(address indexed token, uint256 amount, address to);

    event LogRaffleFinalized(uint256 indexed raffleId);

    event LogWinnersFinalized(uint256 indexed raffleId);
}