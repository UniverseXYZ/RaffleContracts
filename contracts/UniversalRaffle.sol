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

contract UniversalRaffle is 
    IUniversalRaffle,
    ERC721Holder,
    ReentrancyGuard
{
    using SafeMath for uint256;

    constructor(
        uint256 _maxNumberOfSlotsPerRaffle,
        uint256 _nftSlotLimit,
        uint256 _royaltyFeeBps,
        address payable _daoAddress,
        address _raffleTicketAddress,
        address _vrfAddress,
        address[] memory _supportedERC20Tokens,
        IRoyaltiesProvider _royaltiesRegistry
    ) {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();

        ds.maxNumberOfSlotsPerRaffle = _maxNumberOfSlotsPerRaffle;
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
        return UniversalRaffleCore.createRaffle(config);
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

    function buyRaffleTicket(
        uint256 raffleId,
        uint256 amount
    ) external payable override nonReentrant {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();

        UniversalRaffleCore.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleCore.Raffle storage raffle = ds.raffles[raffleId];

        require(raffleId > 0 && raffleId <= ds.totalRaffles, "E01");
        require(!ds.raffles[raffleId].isCanceled, "E04");
        require(ds.raffleConfigs[raffleId].startTime < block.timestamp, "E02");
        require(block.timestamp < raffleInfo.endTime, "E18");
        require(raffle.depositedNFTCounter > 0 && amount > 0, "E19");

        if (ds.raffleConfigs[raffleId].ERC20PurchaseToken == address(1)) {
            uint256 excessAmount = msg.value.sub(amount.mul(raffleInfo.ticketPrice));
            if (excessAmount > 0) {
                (bool returnExcessStatus, ) = (msg.sender).call{value: excessAmount}("");
                require(returnExcessStatus, "Failed to return excess");
            }
        } else {
            IERC20 paymentToken = IERC20(raffleInfo.ERC20PurchaseToken);
            require(paymentToken.transferFrom(msg.sender, address(this), amount.mul(raffleInfo.ticketPrice)), "TX FAILED");
        }

        IRaffleTickets(ds.raffleTicketAddress).mint(msg.sender, amount, raffleId);
    }

    function finalizeRaffle(uint256 raffleId) external override nonReentrant {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        UniversalRaffleCore.RaffleConfig storage raffleInfo = ds.raffleConfigs[raffleId];
        UniversalRaffleCore.Raffle storage raffle = ds.raffles[raffleId];

        require(raffleId > 0 && raffleId <= ds.totalRaffles, "E01");

        require(!raffle.isCanceled, "E04");
        require(block.timestamp > raffleInfo.endTime && !raffle.isFinalized, "E27");

        if (IRaffleTickets(ds.raffleTicketAddress).raffleTicketCounter(raffleId) < raffleInfo.minTicketCount) {
            UniversalRaffleCore.cancelRaffle(raffleId);
        } else {
            IRandomNumberGenerator(ds.vrfAddress).getWinners(raffleId);
        }
    }

    function setWinners(uint256 raffleId, address[] memory winners) public {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        for (uint32 i = 0; i < winners.length; i++) {
            ds.raffles[raffleId].winners[i] = winners[i];
        }
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
        }

        address payable recipient = payable(msg.sender);
        uint256 amount = raffleInfo.ticketPrice.mul(tokenIds.length);

        if (raffleInfo.ERC20PurchaseToken == address(1)) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "TX FAILED");
        } else {
            IERC20 paymentToken = IERC20(raffleInfo.ERC20PurchaseToken);
            require(paymentToken.transferFrom(address(this), msg.sender, amount), "TX FAILED");
        }
    }

    function cancelRaffle(uint256 raffleId) external override {
        return UniversalRaffleCore.cancelRaffle(raffleId);
    }

    function setRoyaltyFeeBps(uint256 _royaltyFeeBps) external override onlyDAO returns (uint256) {
        return UniversalRaffleCore.setRoyaltyFeeBps(_royaltyFeeBps);
    }

    function setNftSlotLimit(uint256 _nftSlotLimit) external override onlyDAO returns (uint256) {
        return UniversalRaffleCore.setNftSlotLimit(_nftSlotLimit);
    }

    function setRoyaltiesRegistry(IRoyaltiesProvider _royaltiesRegistry) external override onlyDAO returns (IRoyaltiesProvider) {
        return UniversalRaffleCore.setRoyaltiesRegistry(_royaltiesRegistry);
    }

    function setSupportedERC20Tokens(address erc20token, bool value) external override onlyDAO returns (address, bool) {
        return UniversalRaffleCore.setSupportedERC20Tokens(erc20token, value);
    }

    function getRaffleInfo(uint256 raffleId) external view override returns (UniversalRaffleCore.RaffleConfig memory, uint256) {
        return UniversalRaffleCore.getRaffleInfo(raffleId);
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
}
