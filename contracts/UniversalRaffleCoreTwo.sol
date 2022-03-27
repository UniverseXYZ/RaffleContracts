// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Forked from Universe Auction House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IRoyaltiesProvider.sol";
import "./lib/LibPart.sol";
import "./UniversalRaffleSchema.sol";

library UniversalRaffleCoreTwo {
    using SafeMath for uint256;

    bytes32 constant STORAGE_POSITION = keccak256("com.universe.raffle.storage");

    function raffleStorage() internal pure returns (UniversalRaffleSchema.Storage storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
        ds.slot := position
        }
    }

    modifier onlyRaffleSetupOwner(uint256 raffleId) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        require(raffleId > 0 &&
                raffleId <= ds.totalRaffles &&
                ds.raffleConfigs[raffleId].startTime > block.timestamp &&
                !ds.raffles[raffleId].isCanceled &&
                ds.raffleConfigs[raffleId].raffler == msg.sender, "E01");
        _;
    }

    function setDepositors(uint256 raffleId, UniversalRaffleSchema.AllowList[] calldata allowList) external onlyRaffleSetupOwner(raffleId) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];

        for (uint256 i; i < allowList.length;) {
            raffle.depositors[allowList[i].participant] = allowList[i].allocation == 1 ? true : false;
            unchecked { i++; }
        }
    }

    function setAllowList(uint256 raffleId, UniversalRaffleSchema.AllowList[] calldata allowList) external onlyRaffleSetupOwner(raffleId) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];

        for (uint256 i; i < allowList.length;) {
            raffle.allowList[allowList[i].participant] = allowList[i].allocation;
            unchecked { i++; }
        }
    }

    function toggleAllowList(uint256 raffleId) external onlyRaffleSetupOwner(raffleId) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];
        raffle.useAllowList = !raffle.useAllowList;
    }

    function buyRaffleTicketsChecks(uint256 raffleId, uint256 amount) external {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];

        if (!raffle.isSetup) {
            bool missing = false;
            for (uint256 i = 1; i <= raffleInfo.totalSlots;) {
                if (raffle.slots[i].depositedNFTCounter < 1) missing = true;
                unchecked { i++; }
            }

            if (!missing) raffle.isSetup = true;
            else raffle.isCanceled = true;
        }

        require(
            raffleId > 0 && raffleId <= ds.totalRaffles &&
            !raffle.isCanceled &&
            raffleInfo.startTime < block.timestamp && 
            block.timestamp < raffleInfo.endTime &&
            raffle.depositedNFTCounter > 0 &&
            amount > 0 && amount <= ds.maxBulkPurchaseCount, "Unavailable");
    }

    function cancelRaffle(uint256 raffleId) external onlyRaffleSetupOwner(raffleId) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();

        require(raffleId > 0 && raffleId <= ds.totalRaffles &&
                ds.raffleConfigs[raffleId].startTime > block.timestamp &&
                !ds.raffles[raffleId].isCanceled, "E01");

        ds.raffles[raffleId].isCanceled = true;

        emit UniversalRaffleSchema.LogRaffleCanceled(raffleId);
    }

    function refundRaffleTickets(uint256 raffleId, uint256[] memory tokenIds) external {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];

        require(raffle.isCanceled, "E04");
        for (uint256 i; i < tokenIds.length;) {
            require(IERC721(ds.raffleTicketAddress).ownerOf(tokenIds[i]) == msg.sender && !raffle.refunds[tokenIds[i]], "Refund already issued");
            raffle.refunds[tokenIds[i]] = true;
            unchecked { i++; }
        }

        uint256 amount = raffleInfo.ticketPrice.mul(tokenIds.length);
        sendPayments(raffleInfo.ERC20PurchaseToken, amount, payable(msg.sender));
    }

    function calculatePaymentSplits(uint256 raffleId) external {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];

        uint256 raffleTotalRevenue = raffleInfo.ticketPrice * raffle.ticketCounter;
        uint256 averageERC721SalePrice = raffleTotalRevenue / raffle.depositedNFTCounter;
        uint256 totalRoyaltyFees = 0;

        for (uint256 i = 1; i <= raffleInfo.totalSlots;) {
            for (uint256 j = 1; j <= raffle.slots[i].depositedNFTCounter;) {
                UniversalRaffleSchema.DepositedNFT storage nft = raffle.slots[i].depositedNFTs[j];

                if (nft.hasSecondarySaleFees) {
                    uint256 value = averageERC721SalePrice;

                    for (uint256 k; k < nft.feesAddress.length && k < 5;) {
                        uint256 fee = (averageERC721SalePrice * nft.feesValue[k]) / 10000;

                        if (value > fee) {
                            value = value.sub(fee);
                            totalRoyaltyFees = totalRoyaltyFees.add(fee);
                        }
                        unchecked { k++; }
                    }
                }
                unchecked { j++; }
            }
            unchecked { i++; }
        }

        // NFT Royalties Split
        ds.rafflesRoyaltyPool[raffleId] = totalRoyaltyFees;

        // DAO Royalties Split
        uint256 daoRoyalty = raffleTotalRevenue.sub(totalRoyaltyFees).mul(ds.royaltyFeeBps).div(10000);
        ds.rafflesDAOPool[raffleId] = daoRoyalty;
        ds.royaltiesReserve[raffleInfo.ERC20PurchaseToken] = ds.royaltiesReserve[raffleInfo.ERC20PurchaseToken].add(daoRoyalty);

        uint256 splitValue = 0;
        uint256 rafflerRevenue = raffleTotalRevenue.sub(totalRoyaltyFees).sub(daoRoyalty);

        for (uint256 i; i < raffleInfo.paymentSplits.length && i < 5;) {
            uint256 fee = (rafflerRevenue * raffleInfo.paymentSplits[i].value) / 10000;
            splitValue = splitValue.add(fee);
            unchecked { i++; }
        }

        // Revenue Split
        ds.raffleRevenue[raffleId] = raffleTotalRevenue.sub(totalRoyaltyFees).sub(splitValue).sub(daoRoyalty);
    }

    function distributeCapturedRaffleRevenue(uint256 raffleId) external {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];

        uint256 raffleRevenue = ds.raffleRevenue[raffleId];
        require(raffleId > 0 && raffleId <= ds.totalRaffles && raffle.isFinalized && raffleRevenue > 0, "E30");

        ds.raffleRevenue[raffleId] = 0;

        uint256 remainder = (raffleInfo.ticketPrice * raffle.ticketCounter).sub(ds.rafflesRoyaltyPool[raffleId]).sub(ds.rafflesDAOPool[raffleId]);
        uint256 value = remainder;
        uint256 paymentSplitsPaid;

        emit UniversalRaffleSchema.LogRaffleRevenueWithdrawal(raffleInfo.raffler, raffleId, remainder);

        // Distribute the payment splits to the respective recipients
        for (uint256 i; i < raffleInfo.paymentSplits.length && i < 5;) {
            uint256 fee = (remainder * raffleInfo.paymentSplits[i].value) / 10000;
            value -= fee;
            paymentSplitsPaid += fee;
            sendPayments(raffleInfo.ERC20PurchaseToken, fee, raffleInfo.paymentSplits[i].recipient);
            unchecked { i++; }
        }

        // Distribute the remaining revenue to the raffler
        sendPayments(raffleInfo.ERC20PurchaseToken, raffleRevenue, raffleInfo.raffler);

        raffle.revenuePaid = true;
    }

    function distributeSecondarySaleFees(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 nftSlotIndex
    ) external {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];

        UniversalRaffleSchema.DepositedNFT storage nft = raffle.slots[slotIndex].depositedNFTs[nftSlotIndex];

        require(raffle.revenuePaid && nft.hasSecondarySaleFees && !nft.feesPaid, "E34");

        uint256 averageERC721SalePrice = raffleInfo.ticketPrice * raffle.ticketCounter / raffle.depositedNFTCounter;

        nft.feesPaid = true;

        for (uint256 i; i < nft.feesAddress.length && i < 5;) {
            uint256 value = (averageERC721SalePrice * nft.feesValue[i]) / 10000;
            if (ds.rafflesRoyaltyPool[raffleId] >= value) {
                ds.rafflesRoyaltyPool[raffleId] = ds.rafflesRoyaltyPool[raffleId].sub(value);
                sendPayments(raffleInfo.ERC20PurchaseToken, value, nft.feesAddress[i]);
            }
            unchecked { i++; }
        }
    }

    function distributeRoyalties(address token) external returns (uint256) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();

        uint256 amountToWithdraw = ds.royaltiesReserve[token];
        require(amountToWithdraw > 0, "E30");

        ds.royaltiesReserve[token] = 0;

        sendPayments(token, amountToWithdraw, ds.daoAddress);
        emit UniversalRaffleSchema.LogRoyaltiesWithdrawal(token, amountToWithdraw, ds.daoAddress);
        return amountToWithdraw;
    }

    function sendPayments(address tokenAddress, uint256 value, address to) internal {
        if (tokenAddress == address(0) && value > 0) {
            (bool success, ) = (to).call{value: value}("");
            require(success, "TX FAILED");
        }

        if (tokenAddress != address(0) && value > 0) {
            SafeERC20.safeTransfer(IERC20(tokenAddress), address(to), value);
        }
    }

}