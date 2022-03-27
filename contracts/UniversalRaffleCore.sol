// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Forked from Universe Auction House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IRoyaltiesProvider.sol";
import "./lib/LibPart.sol";

library UniversalRaffleCore {
    using SafeMath for uint256;

    bytes32 constant STORAGE_POSITION = keccak256("com.universe.raffle.storage");

    struct RaffleConfig {
        address raffler;
        address ERC20PurchaseToken;
        uint256 startTime;
        uint256 endTime;
        uint256 maxTicketCount;
        uint256 minTicketCount;
        uint256 ticketPrice;
        uint32 totalSlots;
        string raffleName;
        string raffleImageURL;
        PaymentSplit[] paymentSplits;
    }

    struct Raffle {
        uint256 ticketCounter;
        uint256 depositedNFTCounter;
        uint256 withdrawnNFTCounter;
        uint256 depositorCount;
        mapping(uint256 => Slot) slots;
        mapping(uint256 => bool) refunds;
        mapping(address => uint256) allowList;
        mapping(address => bool) depositors;
        bool useAllowList;
        bool isCanceled;
        bool isFinalized;
        bool revenuePaid;
    }

    struct RaffleState {
        uint256 ticketCounter;
        uint256 depositedNFTCounter;
        uint256 withdrawnNFTCounter;
        bool useAllowList;
        bool isCanceled;
        bool isFinalized;
        bool revenuePaid;
    }

    struct Slot {
        uint256 depositedNFTCounter;
        uint256 withdrawnNFTCounter;
        uint256 winnerId;
        address winner;
        mapping(uint256 => DepositedNFT) depositedNFTs;
    }

    struct SlotInfo {
        uint256 depositedNFTCounter;
        uint256 withdrawnNFTCounter;
        uint256 winnerId;
        address winner;
    }

    struct SlotIndexAndNFTIndex {
        uint256 slotIndex;
        uint256 NFTIndex;
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
        uint256 value;
    }

    struct AllowList {
        address participant;
        uint32 allocation;
    }

    struct ContractConfigByDAO {
        address daoAddress;
        address raffleTicketAddress;
        address vrfAddress;
        uint256 totalRaffles;
        uint256 maxNumberOfSlotsPerRaffle;
        uint256 maxBulkPurchaseCount;
        uint256 nftSlotLimit;
        uint256 royaltyFeeBps;
        bool daoInitialized;
    }

    struct Storage {
        bool unsafeVRFtesting;
        address vrfAddress;
        address raffleTicketAddress;

        address payable daoAddress;
        bool daoInitialized;

        // DAO Configurable Settings
        uint256 maxNumberOfSlotsPerRaffle;
        uint256 maxBulkPurchaseCount;
        uint256 royaltyFeeBps;
        uint256 nftSlotLimit;
        IRoyaltiesProvider royaltiesRegistry;
        mapping(address => bool) supportedERC20Tokens;

        // Raffle state and data storage
        uint256 totalRaffles;
        mapping(uint256 => RaffleConfig) raffleConfigs;
        mapping(uint256 => Raffle) raffles;
        mapping(uint256 => uint256) raffleRevenue;
        mapping(uint256 => uint256) rafflesDAOPool;
        mapping(uint256 => uint256) rafflesRoyaltyPool;
        mapping(address => uint256) royaltiesReserve;
    }

    function raffleStorage() internal pure returns (Storage storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
        ds.slot := position
        }
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

    event LogERC721RewardsClaim(address indexed claimer, uint256 indexed raffleId, uint256 slotIndex, uint256 amount);

    modifier onlyRaffleSetupOwner(uint256 raffleId) {
        Storage storage ds = raffleStorage();
        require(raffleId > 0 &&
                raffleId <= ds.totalRaffles &&
                ds.raffleConfigs[raffleId].startTime > block.timestamp &&
                !ds.raffles[raffleId].isCanceled &&
                ds.raffleConfigs[raffleId].raffler == msg.sender, "E01");
        _;
    }

    modifier onlyRaffleSetup(uint256 raffleId) {
        Storage storage ds = raffleStorage();
        require(raffleId > 0 &&
                raffleId <= ds.totalRaffles &&
                ds.raffleConfigs[raffleId].startTime > block.timestamp &&
                !ds.raffles[raffleId].isCanceled, "E01");
        _;
    }

    modifier onlyDAO() {
        Storage storage ds = raffleStorage();
        require(msg.sender == ds.daoAddress, "E07");
        _;
    }

    function transferDAOownership(address payable _daoAddress) external onlyDAO {
        Storage storage ds = UniversalRaffleCore.raffleStorage();
        ds.daoAddress = _daoAddress;
        ds.daoInitialized = true;
    }

    function configureRaffle(RaffleConfig calldata config, uint256 existingRaffleId) external returns (uint256) {
        Storage storage ds = raffleStorage();
        uint256 currentTime = block.timestamp;

        require(
            currentTime < config.startTime &&
            config.startTime < config.endTime &&
            config.totalSlots > 0 && config.totalSlots <= ds.maxNumberOfSlotsPerRaffle &&
            config.ERC20PurchaseToken == address(0) || ds.supportedERC20Tokens[config.ERC20PurchaseToken] &&
            config.minTicketCount > 1 && config.maxTicketCount >= config.minTicketCount,
            "Wrong configuration"
        );

        uint256 raffleId;
        if (existingRaffleId > 0) {
            raffleId = existingRaffleId;
            require(ds.raffleConfigs[raffleId].raffler == msg.sender && ds.raffleConfigs[raffleId].startTime > currentTime, "No permission");
            emit LogRaffleEdited(raffleId, msg.sender, config.raffleName);
        } else {
            ds.totalRaffles = ds.totalRaffles + 1;
            raffleId = ds.totalRaffles;

            ds.raffleConfigs[raffleId].raffler = msg.sender;
            ds.raffleConfigs[raffleId].totalSlots = config.totalSlots;

            emit LogRaffleCreated(raffleId, msg.sender, config.raffleName);
        }

        ds.raffleConfigs[raffleId].ERC20PurchaseToken = config.ERC20PurchaseToken;
        ds.raffleConfigs[raffleId].startTime = config.startTime;
        ds.raffleConfigs[raffleId].endTime = config.endTime;
        ds.raffleConfigs[raffleId].maxTicketCount = config.maxTicketCount;
        ds.raffleConfigs[raffleId].minTicketCount = config.minTicketCount;
        ds.raffleConfigs[raffleId].ticketPrice = config.ticketPrice;
        ds.raffleConfigs[raffleId].raffleName = config.raffleName;
        ds.raffleConfigs[raffleId].raffleImageURL = config.raffleImageURL;

        uint256 checkSum = 0;
        delete ds.raffleConfigs[raffleId].paymentSplits;
        for (uint256 k; k < config.paymentSplits.length;) {
            require(config.paymentSplits[k].recipient != address(0) && config.paymentSplits[k].value != 0, "Bad data");
            checkSum += config.paymentSplits[k].value;
            ds.raffleConfigs[raffleId].paymentSplits.push(config.paymentSplits[k]);
            unchecked { k++; }
        }
        require(checkSum < 10000, "E15");

        return raffleId;
    }

    function depositNFTsToRaffle(
        uint256 raffleId,
        uint256[] calldata slotIndices,
        NFT[][] calldata tokens
    ) external onlyRaffleSetup(raffleId) {
        Storage storage ds = raffleStorage();
        RaffleConfig storage raffle = ds.raffleConfigs[raffleId];

        require(
            slotIndices.length <= raffle.totalSlots &&
                slotIndices.length <= 10 &&
                slotIndices.length == tokens.length,
            "E16"
        );

        for (uint256 i; i < slotIndices.length;) {
            require(tokens[i].length <= 5, "E17");
            depositERC721(raffleId, slotIndices[i], tokens[i]);
            unchecked { i++; }
        }
    }

    function depositERC721(
        uint256 raffleId,
        uint256 slotIndex,
        NFT[] calldata tokens
    ) internal returns (uint256[] memory) {
        Storage storage ds = raffleStorage();
        Raffle storage raffle = ds.raffles[raffleId];
        RaffleConfig storage raffleConfig = ds.raffleConfigs[raffleId];

        require(
            (msg.sender == raffleConfig.raffler || raffle.depositors[msg.sender]) &&
            raffleConfig.totalSlots >= slotIndex && slotIndex > 0 && (tokens.length <= 40) &&
            (raffle.slots[slotIndex].depositedNFTCounter + tokens.length <= ds.nftSlotLimit)
        , "E36");

        // Ensure previous slot has depoited NFTs, so there is no case where there is an empty slot between non-empty slots
        if (slotIndex > 1) require(raffle.slots[slotIndex - 1].depositedNFTCounter > 0, "E39");

        uint256 nftSlotIndex = raffle.slots[slotIndex].depositedNFTCounter;
        raffle.slots[slotIndex].depositedNFTCounter += tokens.length;
        raffle.depositedNFTCounter += tokens.length;
        uint256[] memory nftSlotIndexes = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length;) {
            nftSlotIndex++;
            nftSlotIndexes[i] = nftSlotIndex;
            _depositERC721(
                raffleId,
                slotIndex,
                nftSlotIndex,
                tokens[i].tokenId,
                tokens[i].tokenAddress
            );
            unchecked { i++; }
        }

        return nftSlotIndexes;
    }

    function _depositERC721(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 nftSlotIndex,
        uint256 tokenId,
        address tokenAddress
    ) internal returns (uint256) {
        Storage storage ds = raffleStorage();

        (LibPart.Part[] memory nftRoyalties,) = ds.royaltiesRegistry.getRoyalties(tokenAddress, tokenId);

        address[] memory feesAddress = new address[](nftRoyalties.length);
        uint96[] memory feesValue = new uint96[](nftRoyalties.length);
        for (uint256 i; i < nftRoyalties.length && i < 5;) {
            feesAddress[i] = nftRoyalties[i].account;
            feesValue[i] = nftRoyalties[i].value;
            unchecked { i++; }
        }

        IERC721(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenId);

        ds.raffles[raffleId].slots[slotIndex].depositedNFTs[nftSlotIndex] = DepositedNFT({
            tokenId: tokenId,
            tokenAddress: tokenAddress,
            depositor: msg.sender,
            hasSecondarySaleFees: nftRoyalties.length > 0,
            feesPaid: false,
            feesAddress: feesAddress,
            feesValue: feesValue
        });

        emit LogERC721Deposit(
            msg.sender,
            tokenAddress,
            tokenId,
            raffleId,
            slotIndex,
            nftSlotIndex
        );

        return nftSlotIndex;
    }

    function withdrawDepositedERC721(
        uint256 raffleId,
        SlotIndexAndNFTIndex[] calldata slotNftIndexes
    ) external {
        Storage storage ds = raffleStorage();
        Raffle storage raffle = ds.raffles[raffleId];

        require(raffleId > 0 && raffleId <= ds.totalRaffles && ds.raffles[raffleId].isCanceled, "E01");

        raffle.withdrawnNFTCounter += slotNftIndexes.length;
        raffle.depositedNFTCounter -= slotNftIndexes.length;
        for (uint256 i; i < slotNftIndexes.length;) {
            ds.raffles[raffleId].slots[slotNftIndexes[i].slotIndex].withdrawnNFTCounter += 1;
            _withdrawDepositedERC721(
                raffleId,
                slotNftIndexes[i].slotIndex,
                slotNftIndexes[i].NFTIndex
            );
            unchecked { i++; }
        }
    }

    function _withdrawDepositedERC721(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 nftSlotIndex
    ) internal {
        Storage storage ds = raffleStorage();
        DepositedNFT memory nftForWithdrawal = ds.raffles[raffleId].slots[slotIndex].depositedNFTs[
            nftSlotIndex
        ];

        require(msg.sender == nftForWithdrawal.depositor, "E41");
        delete ds.raffles[raffleId].slots[slotIndex].depositedNFTs[nftSlotIndex];

        emit LogERC721Withdrawal(
            msg.sender,
            nftForWithdrawal.tokenAddress,
            nftForWithdrawal.tokenId,
            raffleId,
            slotIndex,
            nftSlotIndex
        );

        IERC721(nftForWithdrawal.tokenAddress).safeTransferFrom(
            address(this),
            nftForWithdrawal.depositor,
            nftForWithdrawal.tokenId
        );
    }

    function buyRaffleTicketsChecks(uint256 raffleId, uint256 amount) external {
        Storage storage ds = raffleStorage();
        RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        Raffle storage raffle = ds.raffles[raffleId];

        require(
            raffleId > 0 && raffleId <= ds.totalRaffles &&
            !raffle.isCanceled &&
            raffleInfo.startTime < block.timestamp && 
            block.timestamp < raffleInfo.endTime &&
            raffle.depositedNFTCounter > 0 &&
            amount > 0 && amount <= ds.maxBulkPurchaseCount, "Unavailable");
    }

    function claimERC721Rewards(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 amount
    ) external {
        Storage storage ds = raffleStorage();

        Raffle storage raffle = ds.raffles[raffleId];
        Slot storage winningSlot = raffle.slots[slotIndex];

        uint256 totalWithdrawn = winningSlot.withdrawnNFTCounter;

        require(raffle.isFinalized &&
                winningSlot.winner == msg.sender &&
                amount <= 40 &&
                amount <= winningSlot.depositedNFTCounter - totalWithdrawn, "E24");

        emit LogERC721RewardsClaim(msg.sender, raffleId, slotIndex, amount);

        raffle.withdrawnNFTCounter += amount;
        raffle.slots[slotIndex].withdrawnNFTCounter = winningSlot.withdrawnNFTCounter += amount;
        for (uint256 i = totalWithdrawn; i < amount + totalWithdrawn;) {
            DepositedNFT memory nftForWithdrawal = winningSlot.depositedNFTs[i + 1];

            IERC721(nftForWithdrawal.tokenAddress).safeTransferFrom(
                address(this),
                msg.sender,
                nftForWithdrawal.tokenId
            );

            unchecked { i++; }
        }
    }

    function setRaffleConfigValue(uint256 configType, uint256 _value) external onlyDAO returns (uint256) {
        Storage storage ds = raffleStorage();

        if (configType == 0) ds.maxNumberOfSlotsPerRaffle = _value;
        else if (configType == 1) ds.maxBulkPurchaseCount = _value;
        else if (configType == 2) ds.nftSlotLimit = _value;
        else if (configType == 3) ds.royaltyFeeBps = _value;

        return _value;
    }

    function setRoyaltiesRegistry(IRoyaltiesProvider _royaltiesRegistry) external onlyDAO returns (IRoyaltiesProvider) {
        Storage storage ds = raffleStorage();
        ds.royaltiesRegistry = _royaltiesRegistry;
        return ds.royaltiesRegistry;
    }

    function setSupportedERC20Tokens(address erc20token, bool value) external onlyDAO returns (address, bool) {
        Storage storage ds = raffleStorage();
        ds.supportedERC20Tokens[erc20token] = value;
        return (erc20token, value);
    }

    function getRaffleState(uint256 raffleId) external view returns (RaffleConfig memory, RaffleState memory)
    {
        Storage storage ds = raffleStorage();
        return (ds.raffleConfigs[raffleId], RaffleState(
            ds.raffles[raffleId].ticketCounter,
            ds.raffles[raffleId].depositedNFTCounter,
            ds.raffles[raffleId].withdrawnNFTCounter,
            ds.raffles[raffleId].useAllowList,
            ds.raffles[raffleId].isCanceled,
            ds.raffles[raffleId].isFinalized,
            ds.raffles[raffleId].revenuePaid
        ));
    }

    function getRaffleFinalize(uint256 raffleId) external view returns (bool, uint256, uint256)
    {
        Storage storage ds = raffleStorage();
        return (ds.raffles[raffleId].isFinalized, ds.raffleConfigs[raffleId].totalSlots, ds.raffles[raffleId].ticketCounter);
    }

    function getAllowList(uint256 raffleId, address participant) external view returns (uint256) {
        Storage storage ds = raffleStorage();
        return ds.raffles[raffleId].allowList[participant];
    }

    function getDepositedNftsInSlot(uint256 raffleId, uint256 slotIndex) external view returns (DepositedNFT[] memory) {
        Storage storage ds = raffleStorage();
        uint256 nftsInSlot = ds.raffles[raffleId].slots[slotIndex].depositedNFTCounter;

        DepositedNFT[] memory nfts = new DepositedNFT[](nftsInSlot);

        for (uint256 i; i < nftsInSlot;) {
            nfts[i] = ds.raffles[raffleId].slots[slotIndex].depositedNFTs[i + 1];
            unchecked { i++; }
        }
        return nfts;
    }

    function getSlotInfo(uint256 raffleId, uint256 slotIndex) external view returns (SlotInfo memory) {
        Storage storage ds = raffleStorage();
        Slot storage slot = ds.raffles[raffleId].slots[slotIndex];
        SlotInfo memory slotInfo = SlotInfo(
            slot.depositedNFTCounter,
            slot.withdrawnNFTCounter,
            slot.winnerId,
            slot.winner
        );
        return slotInfo;
    }

    function getContractConfig() external view returns (ContractConfigByDAO memory) {
        Storage storage ds = raffleStorage();

        return ContractConfigByDAO(
            ds.daoAddress,
            ds.raffleTicketAddress,
            ds.vrfAddress,
            ds.totalRaffles,
            ds.maxNumberOfSlotsPerRaffle,
            ds.maxBulkPurchaseCount,
            ds.nftSlotLimit,
            ds.royaltyFeeBps,
            ds.daoInitialized
        );
    }
}
