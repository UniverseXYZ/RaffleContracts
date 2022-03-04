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
import "./UniversalRaffleCore.sol";

import "hardhat/console.sol";

/* TODO:
 * - Distribute secondary fees
 * - What happens if VRF consumer canceled
 * - Giveaway specify addresses
 */

contract UniversalRaffle is 
    IUniversalRaffle,
    ERC721Holder,
    ReentrancyGuard
{
    using SafeMath for uint256;

    constructor(
        bool _unsafeRandomNumber,
        uint256 _maxNumberOfSlotsPerRaffle,
        uint256 _maxBulkPurchaseCount,
        uint256 _nftSlotLimit,
        uint256 _royaltyFeeBps,
        address payable _daoAddress,
        address _raffleTicketAddress,
        address _vrfAddress,
        address[] memory _supportedERC20Tokens,
        IRoyaltiesProvider _royaltiesRegistry
    ) {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();

        ds.unsafeRandomNumber = _unsafeRandomNumber;
        ds.maxNumberOfSlotsPerRaffle = _maxNumberOfSlotsPerRaffle;
        ds.maxBulkPurchaseCount = _maxBulkPurchaseCount;
        ds.nftSlotLimit = _nftSlotLimit;
        ds.royaltyFeeBps = _royaltyFeeBps;
        ds.royaltiesRegistry = _royaltiesRegistry;
        ds.daoAddress = payable(msg.sender);
        ds.daoInitialized = false;
        for (uint256 i = 0; i < _supportedERC20Tokens.length; i++) {
            ds.supportedERC20Tokens[_supportedERC20Tokens[i]] = true;
        }

        ds.raffleTicketAddress = _raffleTicketAddress;
        ds.vrfAddress = _vrfAddress;
    }

    modifier onlyDAO() {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        require(msg.sender == ds.daoAddress, "E07");
        _;
    }

    function transferDAOownership(address payable _daoAddress) public onlyDAO {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        ds.daoAddress = _daoAddress;
        ds.daoInitialized = true;
    }

    function createRaffle(UniversalRaffleCore.RaffleConfig calldata config) external override returns (uint256) {
        return UniversalRaffleCore.configureRaffle(config, 0);
    }

    function reconfigureRaffle(UniversalRaffleCore.RaffleConfig calldata config, uint256 existingRaffleId) external override returns (uint256) {
        return UniversalRaffleCore.configureRaffle(config, existingRaffleId);
    }

    function setAllowList(uint256 raffleId, UniversalRaffleCore.AllowList[] calldata allowList) external override {
        return UniversalRaffleCore.setAllowList(raffleId, allowList);
    }

    function toggleAllowList(uint256 raffleId) external override {
        return UniversalRaffleCore.toggleAllowList(raffleId);
    }

    function batchDepositToRaffle(
        uint256 raffleId,
        uint256[] calldata slotIndices,
        UniversalRaffleCore.NFT[][] calldata tokens
    ) external override {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        UniversalRaffleCore.RaffleConfig storage raffle = ds.raffleConfigs[raffleId];

        require(
            slotIndices.length <= raffle.totalSlots &&
                slotIndices.length <= 10 &&
                slotIndices.length == tokens.length,
            "E16"
        );

        for (uint256 i = 0; i < slotIndices.length; i += 1) {
            require(tokens[i].length <= 5, "E17");
            depositERC721(raffleId, slotIndices[i], tokens[i]);
        }
    }

    function depositERC721(
      uint256 raffleId,
      uint256 slotIndex,
      UniversalRaffleCore.NFT[] calldata tokens
    ) public override nonReentrant returns (uint256[] memory) {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        UniversalRaffleCore.depositERC721(raffleId, slotIndex, tokens);
    }

    function withdrawDepositedERC721(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 amount
    ) public override nonReentrant {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        UniversalRaffleCore.withdrawDepositedERC721(raffleId, slotIndex, amount);
    }

    function buyRaffleTickets(
        uint256 raffleId,
        uint256 amount
    ) external payable override nonReentrant {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();

        UniversalRaffleCore.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleCore.Raffle storage raffle = ds.raffles[raffleId];

        require(raffleId > 0 && raffleId <= ds.totalRaffles, "E01");
        require(!raffle.isCanceled, "E04");
        require(raffleInfo.startTime < block.timestamp, "E02");
        require(block.timestamp < raffleInfo.endTime, "E18");
        require(raffle.depositedNFTCounter > 0 && amount > 0 && amount <= ds.maxBulkPurchaseCount, "E19");

        if (raffle.useAllowList) {
            require(raffle.allowList[msg.sender] >= amount );
            raffle.allowList[msg.sender] -= amount;
        }

        if (raffleInfo.ERC20PurchaseToken == address(0)) {
            require(msg.value >= amount.mul(raffleInfo.ticketPrice), "Insufficient value");
            uint256 excessAmount = msg.value.sub(amount.mul(raffleInfo.ticketPrice));
            if (excessAmount > 0) {
                (bool returnExcessStatus, ) = (msg.sender).call{value: excessAmount}("");
                require(returnExcessStatus, "Failed to return excess");
            }
        } else {
            IERC20 paymentToken = IERC20(raffleInfo.ERC20PurchaseToken);
            require(paymentToken.transferFrom(msg.sender, address(this), amount.mul(raffleInfo.ticketPrice)), "TX FAILED");
        }

        raffle.ticketCounter += amount;
        IRaffleTickets(ds.raffleTicketAddress).mint(msg.sender, amount, raffleId);
    }

    function finalizeRaffle(uint256 raffleId) external override nonReentrant {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        UniversalRaffleCore.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleCore.Raffle storage raffle = ds.raffles[raffleId];

        require(raffleId > 0 && raffleId <= ds.totalRaffles, "E01");

        require(!raffle.isCanceled, "E04");
        require(block.timestamp > raffleInfo.endTime && !raffle.isFinalized, "E27");

        if (raffle.ticketCounter < raffleInfo.minTicketCount) {
            UniversalRaffleCore.refundRaffle(raffleId);
        } else {
            if (ds.unsafeRandomNumber) IRandomNumberGenerator(ds.vrfAddress).getWinnersMock(raffleId); // Testing purposes only
            else IRandomNumberGenerator(ds.vrfAddress).getWinners(raffleId);
        }
    }

    function setWinners(uint256 raffleId, address[] memory winners) public {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        for (uint32 i = 1; i <= winners.length; i++) {
            ds.raffles[raffleId].winners[i] = winners[i - 1];
            ds.raffles[raffleId].slots[i].winner = winners[i - 1];
        }

        ds.raffles[raffleId].isFinalized = true;
    }

    function claimERC721Rewards(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 amount
    ) external override nonReentrant {
        address claimer = msg.sender;

        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        UniversalRaffleCore.claimERC721Rewards(claimer, raffleId, slotIndex, amount);
    }

    function refundRaffleTickets(uint256 raffleId, uint256[] memory tokenIds)
        external
        override
        nonReentrant
    {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        UniversalRaffleCore.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleCore.Raffle storage raffle = ds.raffles[raffleId];

        require(raffle.isCanceled, "E04");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(IERC721(ds.raffleTicketAddress).ownerOf(tokenIds[i]) == msg.sender);
            require(!raffle.refunds[tokenIds[i]], "Refund already issued");
            raffle.refunds[tokenIds[i]] = true;
        }

        address payable recipient = payable(msg.sender);
        uint256 amount = raffleInfo.ticketPrice.mul(tokenIds.length);

        if (raffleInfo.ERC20PurchaseToken == address(0)) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "TX FAILED");
        } else {
            IERC20 paymentToken = IERC20(raffleInfo.ERC20PurchaseToken);
            require(paymentToken.transfer(msg.sender, amount), "TX FAILED");
        }
    }

    function cancelRaffle(uint256 raffleId) external override {
        return UniversalRaffleCore.cancelRaffle(raffleId);
    }


    // function distributeCapturedRaffleRevenue(uint256 raffleId)
    //     external
    //     override
    //     nonReentrant
    // {
    //     UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
    //     UniversalRaffleCore.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
    //     UniversalRaffleCore.Raffle storage raffle = ds.raffles[raffleId];

    //     require(raffleId > 0 && raffleId <= ds.totalRaffles, "E01");
    //     require(raffle.isFinalized, "E24");

    //     uint256 amountToWithdraw = raffle.ticketCounter.mul(raffleInfo.ticketPrice);
    //     require(amountToWithdraw > 0, "E30");

    //     uint256 value = amountToWithdraw;
    //     uint256 paymentSplitsPaid;

    //     auctionsRevenue[auctionId] = 0;

    //     emit LogAuctionRevenueWithdrawal(auction.auctionOwner, auctionId, amountToWithdraw);

    //     // Distribute the payment splits to the respective recipients
    //     for (uint256 i = 0; i < raffleInfo.paymentSplits.length && i < 5; i += 1) {
    //         FeeCalculate.Fee memory interimFee = value.subFee(
    //             (amountToWithdraw * raffleInfo.paymentSplits[i].value) / 10000
    //         );
    //         value = interimFee.remainingValue;
    //         paymentSplitsPaid = paymentSplitsPaid + interimFee.feeValue;

    //         if (raffleInfo.ERC20PurchaseToken == address(0) && interimFee.feeValue > 0) {
    //             (bool success, ) = raffleInfo.paymentSplits[i].recipient.call{
    //                 value: interimFee.feeValue
    //             }("");
    //             require(success, "TX FAILED");
    //         }

    //         if (raffleInfo.ERC20PurchaseToken != address(0) && interimFee.feeValue > 0) {
    //             IERC20Upgradeable token = IERC20Upgradeable(raffleInfo.ERC20PurchaseToken);
    //             require(
    //                 token.transfer(
    //                     address(raffleInfo.paymentSplits[i].recipient),
    //                     interimFee.feeValue
    //                 ),
    //                 "TX FAILED"
    //             );
    //         }
    //     }

    //     // Distribute the remaining revenue to the auction owner
    //     if (auction.bidToken == address(0)) {
    //         (bool success, ) = payable(auction.auctionOwner).call{
    //             value: amountToWithdraw - paymentSplitsPaid
    //         }("");
    //         require(success, "TX FAILED");
    //     }

    //     if (auction.bidToken != address(0)) {
    //         IERC20Upgradeable bidToken = IERC20Upgradeable(auction.bidToken);
    //         require(
    //             bidToken.transfer(auction.auctionOwner, amountToWithdraw - paymentSplitsPaid),
    //             "TX FAILED"
    //         );
    //     }
    // }

    // function calculateSecondarySaleFees(uint256 auctionId, uint256 slotIndex)
    //     internal
    //     returns (uint256)
    // {
    //     Slot storage slot = auctions[auctionId].slots[slotIndex];

    //     uint256 averageERC721SalePrice = slot.winningBidAmount / slot.totalDepositedNfts;
    //     uint256 totalFeesPayableForSlot = 0;

    //     for (uint256 i = 0; i < slot.totalDepositedNfts; i += 1) {
    //         DepositedERC721 memory nft = slot.depositedNfts[i + 1];

    //         if (nft.hasSecondarySaleFees) {
    //             LibPart.Part[] memory fees = royaltiesRegistry.getRoyalties(
    //                 nft.tokenAddress,
    //                 nft.tokenId
    //             );
    //             uint256 value = averageERC721SalePrice;

    //             for (uint256 j = 0; j < fees.length && j < 5; j += 1) {
    //                 FeeCalculate.Fee memory interimFee = value.subFee(
    //                     (averageERC721SalePrice * (fees[j].value)) / (10000)
    //                 );
    //                 value = interimFee.remainingValue;
    //                 totalFeesPayableForSlot = totalFeesPayableForSlot + (interimFee.feeValue);
    //             }
    //         }
    //     }

    //     return totalFeesPayableForSlot;
    // }

    // function distributeSecondarySaleFees(
    //     uint256 raffleId,
    //     uint256 slotIndex,
    //     uint256 nftSlotIndex
    // ) external override {
    //     UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();

    //     UniversalRaffleCore.Raffle storage raffle = ds.raffles[raffleId];
    //     UniversalRaffleCore.Slot storage slot = raffle.slots[slotIndex];
    //     UniversalRaffleCore.DepositedNFT storage nft = slot.depositedNFTs[nftSlotIndex];

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
    //     UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();

    //     uint256 amountToWithdraw = ds.royaltiesReserve[token];
    //     require(amountToWithdraw > 0, "E30");

    //     ds.royaltiesReserve[token] = 0;

    //     // emit LogRoyaltiesWithdrawal(amountToWithdraw, ds.daoAddress, token);

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

    function setMaxBulkPurchaseCount(uint256 _maxBulkPurchaseCount) external override onlyDAO returns (uint256) {
        return UniversalRaffleCore.setMaxBulkPurchaseCount(_maxBulkPurchaseCount);
    }

    function setNftSlotLimit(uint256 _nftSlotLimit) external override onlyDAO returns (uint256) {
        return UniversalRaffleCore.setNftSlotLimit(_nftSlotLimit);
    }

    function setRoyaltyFeeBps(uint256 _royaltyFeeBps) external override onlyDAO returns (uint256) {
        return UniversalRaffleCore.setRoyaltyFeeBps(_royaltyFeeBps);
    }

    function setRoyaltiesRegistry(IRoyaltiesProvider _royaltiesRegistry) external override onlyDAO returns (IRoyaltiesProvider) {
        return UniversalRaffleCore.setRoyaltiesRegistry(_royaltiesRegistry);
    }

    function setSupportedERC20Tokens(address erc20token, bool value) external override onlyDAO returns (address, bool) {
        return UniversalRaffleCore.setSupportedERC20Tokens(erc20token, value);
    }

    function getRaffleConfig(uint256 raffleId) external view override returns (UniversalRaffleCore.RaffleConfig memory) {
        return UniversalRaffleCore.getRaffleConfig(raffleId);
    }

    function getRaffleState(uint256 raffleId) external view override returns (UniversalRaffleCore.RaffleState memory) {
        return UniversalRaffleCore.getRaffleState(raffleId);
    }

    function getAllowList(uint256 raffleId, address participant) external view override returns (uint256) {
        return UniversalRaffleCore.getAllowList(raffleId, participant);
    }

    function getDepositedNftsInSlot(uint256 raffleId, uint256 slotIndex) external view override 
        returns (UniversalRaffleCore.DepositedNFT[] memory) {
        return UniversalRaffleCore.getDepositedNftsInSlot(raffleId, slotIndex);
    }

    function getSlotInfo(uint256 raffleId, uint256 slotIndex) external view override returns (UniversalRaffleCore.SlotInfo memory) {
        return UniversalRaffleCore.getSlotInfo(raffleId, slotIndex);
    }

    function getSlotWinner(uint256 raffleId, uint256 slotIndex) external view override returns (address) {
        return UniversalRaffleCore.getSlotWinner(raffleId, slotIndex);
    }

    function getContractConfig() external view override returns (UniversalRaffleCore.ContractConfigByDAO memory) {
        return UniversalRaffleCore.getContractConfig();
    }
}
