// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Forked from Universe Auction House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IRaffleTickets.sol";
import "./interfaces/IRandomNumberGenerator.sol";
import "./interfaces/IUniversalRaffle.sol";
import "./interfaces/IRoyaltiesProvider.sol";
import "./lib/LibPart.sol";
import "./lib/FeeCalculate.sol";

import "hardhat/console.sol";

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
        PaymentSplit[] paymentSplits;
    }

    struct Raffle {
        uint256 vrfNumber;
        uint256 ticketCounter;
        uint256 depositedNFTCounter;
        uint256 withdrawnNFTCounter;
        mapping(uint256 => Slot) slots;
        mapping(address => uint256) allowList;
        mapping(address => uint256) entriesPerAddress;
        mapping(uint256 => address) entries;
        mapping(uint256 => address) winners;
        mapping(uint256 => bool) refunds;
        bool useAllowList;
        bool isCanceled;
        bool isFinalized;
    }

    struct Slot {
        uint256 depositedNFTCounter;
        uint256 withdrawnNFTCounter;
        address winner;
        mapping(uint256 => DepositedNFT) depositedNFTs;
    }

    struct SlotInfo {
        uint256 depositedNFTCounter;
        uint256 withdrawnNFTCounter;
        address winner;
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
    }

    struct PaymentSplit {
        address payable recipient;
        uint256 value;
    }

    struct Storage { 
        address vrfAddress;
        address raffleTicketAddress;

        address payable daoAddress;
        bool daoInitialized;
        uint256 maxNumberOfSlotsPerRaffle;
        uint256 maxBulkPurchaseCount;
        uint256 royaltyFeeBps;
        uint256 nftSlotLimit;

        uint256 totalRaffles;
        mapping(uint256 => RaffleConfig) raffleConfigs;
        mapping(uint256 => Raffle) raffles;
        mapping(uint256 => uint256) rafflesRevenue;
        mapping(address => uint256) royaltiesReserve;
        mapping(address => bool) supportedERC20Tokens;

        IRoyaltiesProvider royaltiesRegistry;
    }

    function raffleStorage() internal pure returns (Storage storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
        ds.slot := position
        }
    }


    event LogERC721Deposit(
        address depositor,
        address tokenAddress,
        uint256 tokenId,
        uint256 raffleId,
        uint256 slotIndex,
        uint256 nftSlotIndex
    );

    event LogERC721Withdrawal(
        address depositor,
        address tokenAddress,
        uint256 tokenId,
        uint256 raffleId,
        uint256 slotIndex,
        uint256 nftSlotIndex
    );

    event LogRaffleCreated(
        uint256 raffleId,
        address raffleOwner,
        uint256 numberOfSlots,
        uint256 startTime,
        uint256 endTime,
        uint256 resetTimer
    );

    event LogBidMatched(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 slotReservePrice,
        uint256 winningBidAmount,
        address winner
    );

    event LogSlotRevenueCaptured(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 amount,
        address ERC20PurchaseToken
    );

    event LogBidSubmitted(address sender, uint256 raffleId, uint256 currentBid, uint256 totalBid);

    event LogBidWithdrawal(address recipient, uint256 raffleId, uint256 amount);

    event LogRaffleExtended(uint256 raffleId, uint256 endTime);

    event LogRaffleCanceled(uint256 raffleId);

    event LogRaffleRevenueWithdrawal(address recipient, uint256 raffleId, uint256 amount);

    event LogERC721RewardsClaim(address claimer, uint256 raffleId, uint256 slotIndex);

    event LogRoyaltiesWithdrawal(uint256 amount, address to, address token);

    event LogRaffleFinalized(uint256 raffleId);



    modifier onlyExistingRaffle(uint256 raffleId) {
        Storage storage ds = raffleStorage();
        require(raffleId > 0 && raffleId <= ds.totalRaffles, "E01");
        _;
    }

    modifier onlyRaffleStarted(uint256 raffleId) {
        Storage storage ds = raffleStorage();
        require(ds.raffleConfigs[raffleId].startTime < block.timestamp, "E02");
        _;
    }

    modifier onlyRaffleNotStarted(uint256 raffleId) {
        Storage storage ds = raffleStorage();
        require(ds.raffleConfigs[raffleId].startTime > block.timestamp, "E03");
        _;
    }

    modifier onlyRaffleNotCanceled(uint256 raffleId) {
        Storage storage ds = raffleStorage();
        require(!ds.raffles[raffleId].isCanceled, "E04");
        _;
    }

    modifier onlyRaffleCanceled(uint256 raffleId) {
        Storage storage ds = raffleStorage();
        require(ds.raffles[raffleId].isCanceled, "E05");
        _;
    }

    modifier onlyRaffleOwner(uint256 raffleId) {
        Storage storage ds = raffleStorage();
        require(ds.raffleConfigs[raffleId].raffler == msg.sender, "E06");
        _;
    }

    modifier onlyDAO() {
        Storage storage ds = raffleStorage();
        require(msg.sender == ds.daoAddress, "E07");
        _;
    }


    function transferDAOownership(address payable _daoAddress) public onlyDAO {
        Storage storage ds = raffleStorage();
        ds.daoAddress = _daoAddress;
        ds.daoInitialized = true;
    }

    function configureRaffle(RaffleConfig calldata config, uint256 existingRaffleId) external returns (uint256) {
        Storage storage ds = raffleStorage();
        uint256 currentTime = block.timestamp;

        require(
            currentTime < config.startTime &&
            config.startTime < config.endTime,
            "Wrong time configuration"
        );

        require(
            config.totalSlots > 0 && config.totalSlots <= ds.maxNumberOfSlotsPerRaffle,
            "Slots are out of bounds"
        );

        require(ds.supportedERC20Tokens[config.ERC20PurchaseToken], "The ERC20 token is not supported");
        require(config.minTicketCount > 1 && config.maxTicketCount >= config.minTicketCount, "Ticket count err");

        uint256 raffleId;
        if (existingRaffleId > 0) {
            require(ds.raffleConfigs[existingRaffleId].raffler == msg.sender, "No permission");
            require(ds.raffleConfigs[raffleId].startTime > block.timestamp, "Raffle already started");
            raffleId = existingRaffleId;
        } else {
            ds.totalRaffles = ds.totalRaffles + 1;
            raffleId = ds.totalRaffles;

            // Can only be initialized and not reconfigurable
            ds.raffles[raffleId].ticketCounter = 0;
            ds.raffles[raffleId].depositedNFTCounter = 0;
            ds.raffles[raffleId].withdrawnNFTCounter = 0;
            ds.raffles[raffleId].useAllowList = false;
            ds.raffles[raffleId].isCanceled = false;
            ds.raffles[raffleId].isFinalized = false;

            ds.raffleConfigs[raffleId].raffler = msg.sender;
            ds.raffleConfigs[raffleId].totalSlots = config.totalSlots;
        }

        ds.raffleConfigs[raffleId].ERC20PurchaseToken = config.ERC20PurchaseToken;
        ds.raffleConfigs[raffleId].startTime = config.startTime;
        ds.raffleConfigs[raffleId].endTime = config.endTime;
        ds.raffleConfigs[raffleId].maxTicketCount = config.maxTicketCount;
        ds.raffleConfigs[raffleId].minTicketCount = config.minTicketCount;
        ds.raffleConfigs[raffleId].ticketPrice = config.ticketPrice;

        uint256 checkSum = 0;
        delete ds.raffleConfigs[raffleId].paymentSplits;
        for (uint256 k = 0; k < config.paymentSplits.length; k += 1) {
            require(config.paymentSplits[k].recipient != address(0), "Recipient should be present");
            require(config.paymentSplits[k].value != 0, "Fee value should be positive");
            checkSum += config.paymentSplits[k].value;
            ds.raffleConfigs[raffleId].paymentSplits.push(config.paymentSplits[k]);
        }
        require(checkSum < 10000, "E15");

        return raffleId;
    }

    function depositERC721Checks(
        uint256 raffleId,
        uint256 slotIndex,
        NFT[] calldata tokens
    ) private {
        Storage storage ds = raffleStorage();
        Raffle storage raffle = ds.raffles[raffleId];
        RaffleConfig storage raffleConfig = ds.raffleConfigs[raffleId];

        require(msg.sender == raffleConfig.raffler, "E36");
        require(raffleConfig.totalSlots >= slotIndex && slotIndex > 0, "E29");
        require((tokens.length <= 40), "E37");
        require(
            (raffle.slots[slotIndex].depositedNFTCounter + tokens.length <=
                ds.nftSlotLimit),
            "E38"
        );

        // Ensure previous slot has depoited NFTs, so there is no case where there is an empty slot between non-empty slots
        if (slotIndex > 1) {
            require(raffle.slots[slotIndex - 1].depositedNFTCounter > 0, "E39");
        }
    }

    function depositERC721(
        uint256 raffleId,
        uint256 slotIndex,
        NFT[] calldata tokens
    )
        public
        onlyExistingRaffle(raffleId)
        onlyRaffleNotStarted(raffleId)
        onlyRaffleNotCanceled(raffleId)
        returns (uint256[] memory)
    {
        depositERC721Checks(raffleId, slotIndex, tokens);

        uint256[] memory nftSlotIndexes = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i += 1) {
            nftSlotIndexes[i] = _depositERC721(
                raffleId,
                slotIndex,
                tokens[i].tokenId,
                tokens[i].tokenAddress
            );
        }

        return nftSlotIndexes;
    }

    function _depositERC721(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 tokenId,
        address tokenAddress
    ) internal returns (uint256) {
        Storage storage ds = raffleStorage();
        Raffle storage raffle = ds.raffles[raffleId];
        Slot storage slot = raffle.slots[slotIndex];

        DepositedNFT memory item = DepositedNFT({
            tokenId: tokenId,
            tokenAddress: tokenAddress,
            depositor: msg.sender,
            hasSecondarySaleFees: ds.royaltiesRegistry.getRoyalties(tokenAddress, tokenId).length > 0,
            feesPaid: false
        });

        IERC721(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenId);

        uint256 nftSlotIndex = slot.depositedNFTCounter + 1;

        slot.depositedNFTs[nftSlotIndex] = item;
        slot.depositedNFTCounter = nftSlotIndex;
        raffle.depositedNFTCounter = raffle.depositedNFTCounter + 1;

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
        uint256 slotIndex,
        uint256 amount
    ) public  onlyExistingRaffle(raffleId) onlyRaffleCanceled(raffleId) {
        Storage storage ds = raffleStorage();
        Raffle storage raffle = ds.raffles[raffleId];
        Slot storage slot = raffle.slots[slotIndex];

        uint256 totalDeposited = slot.depositedNFTCounter;
        uint256 totalWithdrawn = slot.withdrawnNFTCounter;

        require(amount <= 40, "E25");
        require(amount <= totalDeposited - totalWithdrawn, "E26");

        for (uint256 i = totalWithdrawn; i < amount + totalWithdrawn; i += 1) {
            _withdrawDepositedERC721(
                raffleId,
                slotIndex,
                i + 1
            );
        }
    }

    function _withdrawDepositedERC721(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 nftSlotIndex
    ) internal returns (uint256) {
        Storage storage ds = raffleStorage();
        Raffle storage raffle = ds.raffles[raffleId];
        Slot storage slot = raffle.slots[slotIndex];

        DepositedNFT memory nftForWithdrawal = slot.depositedNFTs[
            nftSlotIndex
        ];

        require(msg.sender == nftForWithdrawal.depositor, "E41");

        delete slot.depositedNFTs[nftSlotIndex];

        raffle.withdrawnNFTCounter = raffle.withdrawnNFTCounter + 1;
        raffle.depositedNFTCounter = raffle.depositedNFTCounter - 1;
        slot.withdrawnNFTCounter =
            slot.withdrawnNFTCounter +
            1;

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

    function claimERC721Rewards(
        address claimer,
        uint256 raffleId,
        uint256 slotIndex,
        uint256 amount
    ) external {
        Storage storage ds = raffleStorage();

        Raffle storage raffle = ds.raffles[raffleId];
        Slot storage winningSlot = raffle.slots[slotIndex];

        uint256 totalDeposited = winningSlot.depositedNFTCounter;
        uint256 totalWithdrawn = winningSlot.withdrawnNFTCounter;

        require(raffle.isFinalized, "E24");
        require(raffle.winners[slotIndex] == claimer, "E31");

        require(amount <= 40, "E25");
        require(amount <= totalDeposited - totalWithdrawn, "E33");

        emit LogERC721RewardsClaim(claimer, raffleId, slotIndex);

        for (uint256 i = totalWithdrawn; i < amount + totalWithdrawn; i += 1) {
            DepositedNFT memory nftForWithdrawal = winningSlot.depositedNFTs[i + 1];

            raffle.withdrawnNFTCounter = raffle.withdrawnNFTCounter + 1;
            raffle.slots[slotIndex].withdrawnNFTCounter =
                winningSlot.withdrawnNFTCounter +
                1;

            if (nftForWithdrawal.tokenId != 0) {
                IERC721(nftForWithdrawal.tokenAddress).safeTransferFrom(
                    address(this),
                    claimer,
                    nftForWithdrawal.tokenId
                );
            }
        }
    }

    function cancelRaffle(uint256 raffleId)
        external
        
        onlyExistingRaffle(raffleId)
        onlyRaffleNotStarted(raffleId)
        onlyRaffleNotCanceled(raffleId)
        onlyRaffleOwner(raffleId)
    {
        Storage storage ds = raffleStorage();
        ds.raffles[raffleId].isCanceled = true;

        emit LogRaffleCanceled(raffleId);
    }

    // function distributeSecondarySaleFees(
    //     uint256 raffleId,
    //     uint256 slotIndex,
    //     uint256 nftSlotIndex
    // ) external override {
    //     Storage storage ds = raffleStorage();

    //     Raffle storage raffle = ds.raffles[raffleId];
    //     Slot storage slot = raffle.slots[slotIndex];
    //     DepositedNFT storage nft = slot.depositedNFTs[nftSlotIndex];

    //     require(nft.hasSecondarySaleFees && !nft.feesPaid, "E34");
    //     require(slot.revenueCaptured, "E35");

    //     uint256 averageERC721SalePrice = slot.winningBidAmount / slot.totalDepositedNfts;

    //     LibPart.Part[] memory fees = ds.royaltiesRegistry.getRoyalties(nft.tokenAddress, nft.tokenId);
    //     uint256 value = averageERC721SalePrice;
    //     nft.feesPaid = true;

    //     for (uint256 i = 0; i < fees.length && i < 5; i += 1) {
    //         FeeCalculate.Fee memory interimFee = value.subFee(
    //             (averageERC721SalePrice * (fees[i].value)) / (10000)
    //         );
    //         value = interimFee.remainingValue;

    //         if (raffle.ERC20PurchaseToken == address(0) && interimFee.feeValue > 0) {
    //             (bool success, ) = (fees[i].account).call{value: interimFee.feeValue}("");
    //             require(success, "TX FAILED");
    //         }

    //         if (raffle.ERC20PurchaseToken != address(0) && interimFee.feeValue > 0) {
    //             IERC20 token = IERC20(raffle.ERC20PurchaseToken);
    //             require(token.transfer(address(fees[i].account), interimFee.feeValue), "TX FAILED");
    //         }
    //     }
    // }

    // function distributeRoyalties(address token) external onlyDAO returns (uint256) {
    //     Storage storage ds = raffleStorage();

    //     uint256 amountToWithdraw = ds.royaltiesReserve[token];
    //     require(amountToWithdraw > 0, "E30");

    //     ds.royaltiesReserve[token] = 0;

    //     emit LogRoyaltiesWithdrawal(amountToWithdraw, ds.daoAddress, token);

    //     if (token == address(0)) {
    //         (bool success, ) = payable(ds.daoAddress).call{value: amountToWithdraw}("");
    //         require(success, "TX FAILED");
    //     }

    //     if (token != address(0)) {
    //         IERC20 erc20token = IERC20(token);
    //         require(erc20token.transfer(ds.daoAddress, amountToWithdraw), "TX TX FAILED");
    //     }

    //     return amountToWithdraw;
    // }

    function setRoyaltyFeeBps(uint256 _royaltyFeeBps) external onlyDAO returns (uint256) {
        Storage storage ds = raffleStorage();
        ds.royaltyFeeBps = _royaltyFeeBps;
        return ds.royaltyFeeBps;
    }

    function setMaxBulkPurchaseCount(uint256 _maxBulkPurchaseCount) external onlyDAO returns (uint256) {
        Storage storage ds = raffleStorage();
        ds.maxBulkPurchaseCount = _maxBulkPurchaseCount;
        return ds.maxBulkPurchaseCount;
    }

    function setNftSlotLimit(uint256 _nftSlotLimit) external onlyDAO returns (uint256) {
        Storage storage ds = raffleStorage();
        ds.nftSlotLimit = _nftSlotLimit;
        return ds.nftSlotLimit;
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

    function getRaffleInfo(uint256 raffleId) external view returns (RaffleConfig memory, uint256) {
        Storage storage ds = raffleStorage();
        return (ds.raffleConfigs[raffleId], ds.raffles[raffleId].ticketCounter);
    }

    function getDepositedNftsInSlot(uint256 raffleId, uint256 slotIndex) external view returns (DepositedNFT[] memory) {
        Storage storage ds = raffleStorage();
        uint256 nftsInSlot = ds.raffles[raffleId].slots[slotIndex].depositedNFTCounter;

        DepositedNFT[] memory nfts = new DepositedNFT[](nftsInSlot);

        for (uint256 i = 0; i < nftsInSlot; i += 1) {
            nfts[i] = ds.raffles[raffleId].slots[slotIndex].depositedNFTs[i + 1];
        }
        return nfts;
    }

    function getSlotInfo(uint256 raffleId, uint256 slotIndex) external view returns (SlotInfo memory) {
        Storage storage ds = raffleStorage();
        Slot storage slot = ds.raffles[raffleId].slots[slotIndex];
        SlotInfo memory slotInfo = SlotInfo(
            slot.depositedNFTCounter,
            slot.withdrawnNFTCounter,
            slot.winner
        );
        return slotInfo;
    }

    function getSlotWinner(uint256 raffleId, uint256 slotIndex) external view returns (address) {
        Storage storage ds = raffleStorage();
        return ds.raffles[raffleId].winners[slotIndex];
    }
}
