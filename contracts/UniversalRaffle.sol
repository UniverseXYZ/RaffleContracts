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
import "./UniversalRaffleCore.sol";

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

    function transferDAOownership(address payable _daoAddress) external onlyDAO {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        ds.daoAddress = _daoAddress;
        ds.daoInitialized = true;
    }

    function getRaffleData(uint256 raffleId) private returns (
        UniversalRaffleCore.Storage storage,
        UniversalRaffleCore.RaffleConfig storage,
        UniversalRaffleCore.Raffle storage
    ) {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        return (
            ds,
            ds.raffleConfigs[raffleId],
            ds.raffles[raffleId]
        );
    }

    function createRaffle(UniversalRaffleCore.RaffleConfig calldata config) external override returns (uint256) {
        return UniversalRaffleCore.configureRaffle(config, 0);
    }

    function reconfigureRaffle(UniversalRaffleCore.RaffleConfig calldata config, uint256 existingRaffleId) external override returns (uint256) {
        return UniversalRaffleCore.configureRaffle(config, existingRaffleId);
    }

    function setDepositors(uint256 raffleId, UniversalRaffleCore.AllowList[] calldata allowList) external override {
        return UniversalRaffleCore.setDepositors(raffleId, allowList);
    }

    function setAllowList(uint256 raffleId, UniversalRaffleCore.AllowList[] calldata allowList) external override {
        return UniversalRaffleCore.setAllowList(raffleId, allowList);
    }

    function toggleAllowList(uint256 raffleId) external override {
        return UniversalRaffleCore.toggleAllowList(raffleId);
    }

    function depositNFTsToRaffle(
        uint256 raffleId,
        uint256[] calldata slotIndices,
        UniversalRaffleCore.NFT[][] calldata tokens
    ) external override {
        (
            UniversalRaffleCore.Storage storage ds,
            UniversalRaffleCore.RaffleConfig storage raffle,
        ) = getRaffleData(raffleId);

        require(
            slotIndices.length <= raffle.totalSlots &&
                slotIndices.length <= 10 &&
                slotIndices.length == tokens.length,
            "E16"
        );

        for (uint256 i = 0; i < slotIndices.length; i += 1) {
            require(tokens[i].length <= 5, "E17");
            UniversalRaffleCore.depositERC721(raffleId, slotIndices[i], tokens[i]);
        }
    }

    function withdrawDepositedERC721(
        uint256 raffleId,
        uint256[][] calldata slotNftIndexes
    ) external override nonReentrant {
        UniversalRaffleCore.withdrawDepositedERC721(raffleId, slotNftIndexes);
    }

    function buyRaffleTickets(
        uint256 raffleId,
        uint256 amount
    ) external payable override nonReentrant {
        (
            UniversalRaffleCore.Storage storage ds,
            UniversalRaffleCore.RaffleConfig storage raffleInfo,
            UniversalRaffleCore.Raffle storage raffle
        ) = getRaffleData(raffleId);

        require(raffleId > 0 && raffleId <= ds.totalRaffles, "E01");
        require(
            !raffle.isCanceled &&
            raffleInfo.startTime < block.timestamp && 
            block.timestamp < raffleInfo.endTime &&
            raffle.depositedNFTCounter > 0, "Unavailable");
        require(amount > 0 && amount <= ds.maxBulkPurchaseCount, "Wrong amount");

        if (raffle.useAllowList) {
            require(raffle.allowList[msg.sender] >= amount);
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
        (
            UniversalRaffleCore.Storage storage ds,
            UniversalRaffleCore.RaffleConfig storage raffleInfo,
            UniversalRaffleCore.Raffle storage raffle
        ) = getRaffleData(raffleId);

        require(raffleId > 0 && raffleId <= ds.totalRaffles &&
                !raffle.isCanceled &&
                block.timestamp > raffleInfo.endTime && !raffle.isFinalized, "E01");

        if (raffle.ticketCounter < raffleInfo.minTicketCount) {
            UniversalRaffleCore.refundRaffle(raffleId);
        } else {
            if (ds.unsafeRandomNumber) IRandomNumberGenerator(ds.vrfAddress).getWinnersMock(raffleId); // Testing purposes only
            else IRandomNumberGenerator(ds.vrfAddress).getWinners(raffleId);
            UniversalRaffleCore.calculatePaymentSplits(raffleId);
        }
    }

    function setWinners(uint256 raffleId, address[] memory winners) external {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        require(msg.sender == ds.vrfAddress, "No permission");
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
        UniversalRaffleCore.claimERC721Rewards(raffleId, slotIndex, amount);
    }

    function refundRaffleTickets(uint256 raffleId, uint256[] memory tokenIds)
        external
        override
        nonReentrant
    {
        (
            UniversalRaffleCore.Storage storage ds,
            UniversalRaffleCore.RaffleConfig storage raffleInfo,
            UniversalRaffleCore.Raffle storage raffle
        ) = getRaffleData(raffleId);

        require(raffle.isCanceled, "E04");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(IERC721(ds.raffleTicketAddress).ownerOf(tokenIds[i]) == msg.sender);
            require(!raffle.refunds[tokenIds[i]], "Refund already issued");
            raffle.refunds[tokenIds[i]] = true;
        }

        uint256 amount = raffleInfo.ticketPrice.mul(tokenIds.length);
        sendPayments(raffleInfo.ERC20PurchaseToken, amount, payable(msg.sender));
    }

    function cancelRaffle(uint256 raffleId) external override {
        return UniversalRaffleCore.cancelRaffle(raffleId);
    }

    function distributeCapturedRaffleRevenue(uint256 raffleId)
        external
        override
        nonReentrant
    {
        (
            UniversalRaffleCore.Storage storage ds,
            UniversalRaffleCore.RaffleConfig storage raffleInfo,
            UniversalRaffleCore.Raffle storage raffle
        ) = getRaffleData(raffleId);

        require(raffleId > 0 && raffleId <= ds.totalRaffles && raffle.isFinalized, "E01");

        uint256 raffleRevenue = ds.raffleRevenue[raffleId];
        uint256 raffleTotalRevenue = raffleInfo.ticketPrice * raffle.ticketCounter;
        uint256 daoRoyalty = raffleTotalRevenue.sub(ds.rafflesRoyaltyPool[raffleId]).mul(ds.royaltyFeeBps).div(10000);
        uint256 remainder = raffleTotalRevenue.sub(ds.rafflesRoyaltyPool[raffleId]).sub(daoRoyalty);
        require(raffleRevenue > 0, "E30");

        ds.raffleRevenue[raffleId] = 0;

        uint256 value = remainder;
        uint256 paymentSplitsPaid;

        emit UniversalRaffleCore.LogRaffleRevenueWithdrawal(raffleInfo.raffler, raffleId, remainder);

        // Distribute the payment splits to the respective recipients
        for (uint256 i = 0; i < raffleInfo.paymentSplits.length && i < 5; i += 1) {
            uint256 fee = (remainder * raffleInfo.paymentSplits[i].value) / 10000;
            value -= fee;
            paymentSplitsPaid += fee;
            sendPayments(raffleInfo.ERC20PurchaseToken, fee, raffleInfo.paymentSplits[i].recipient);
        }

        // Distribute the remaining revenue to the raffler
        sendPayments(raffleInfo.ERC20PurchaseToken, raffleRevenue, raffleInfo.raffler);

        raffle.revenuePaid = true;
    }

    function distributeSecondarySaleFees(
        uint256 raffleId,
        uint256 slotIndex,
        uint256 nftSlotIndex
    ) external override nonReentrant {
        (
            UniversalRaffleCore.Storage storage ds,
            UniversalRaffleCore.RaffleConfig storage raffleInfo,
            UniversalRaffleCore.Raffle storage raffle
        ) = getRaffleData(raffleId);

        UniversalRaffleCore.DepositedNFT storage nft = raffle.slots[slotIndex].depositedNFTs[nftSlotIndex];

        require(raffle.revenuePaid && nft.hasSecondarySaleFees && !nft.feesPaid, "E34");

        uint256 averageERC721SalePrice = raffleInfo.ticketPrice * raffle.ticketCounter / raffle.depositedNFTCounter;

        LibPart.Part[] memory fees = ds.royaltiesRegistry.getRoyalties(nft.tokenAddress, nft.tokenId);
        nft.feesPaid = true;

        for (uint256 i = 0; i < fees.length && i < 5; i += 1) {
            uint256 value = (averageERC721SalePrice * fees[i].value) / 10000;
            if (ds.rafflesRoyaltyPool[raffleId] >= value) {
                ds.rafflesRoyaltyPool[raffleId] = ds.rafflesRoyaltyPool[raffleId].sub(value);
                sendPayments(raffleInfo.ERC20PurchaseToken, value, fees[i].account);
            }
        }
    }

    function distributeRoyalties(address token) external nonReentrant returns (uint256) {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();

        uint256 amountToWithdraw = ds.royaltiesReserve[token];
        require(amountToWithdraw > 0, "E30");

        ds.royaltiesReserve[token] = 0;

        sendPayments(token, amountToWithdraw, ds.daoAddress);
        return amountToWithdraw;
    }

    function sendPayments(address tokenAddress, uint256 value, address to) internal {
        if (tokenAddress == address(0) && value > 0) {
            (bool success, ) = (to).call{value: value}("");
            require(success, "TX FAILED");
        }

        if (tokenAddress != address(0) && value > 0) {
            IERC20 token = IERC20(tokenAddress);
            require(token.transfer(address(to), value), "TX FAILED");
        }
    }

    function setRaffleConfigValue(uint256 configType, uint256 _value) external override returns (uint256) {
        return UniversalRaffleCore.setRaffleConfigValue(configType, _value);
    }

    function setRoyaltiesRegistry(IRoyaltiesProvider _royaltiesRegistry) external override returns (IRoyaltiesProvider) {
        return UniversalRaffleCore.setRoyaltiesRegistry(_royaltiesRegistry);
    }

    function setSupportedERC20Tokens(address erc20token, bool value) external override returns (address, bool) {
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
