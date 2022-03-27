// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Forked from Universe Auction House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IRaffleTickets.sol";
import "./interfaces/IRandomNumberGenerator.sol";
import "./interfaces/IUniversalRaffle.sol";
import "./interfaces/IRoyaltiesProvider.sol";
import "./lib/LibPart.sol";
import "./UniversalRaffleCore.sol";
import "./UniversalRaffleCoreTwo.sol";

/* TODO:
 * Ensure no empty slots upon raffle
 * Return allowed depositors
 */

contract UniversalRaffle is 
    IUniversalRaffle,
    ERC721Holder,
    ReentrancyGuard
{
    using SafeMath for uint256;

    constructor(
        bool _unsafeVRFtesting,
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

        ds.unsafeVRFtesting = _unsafeVRFtesting;
        ds.maxNumberOfSlotsPerRaffle = _maxNumberOfSlotsPerRaffle;
        ds.maxBulkPurchaseCount = _maxBulkPurchaseCount;
        ds.nftSlotLimit = _nftSlotLimit;
        ds.royaltyFeeBps = _royaltyFeeBps;
        ds.royaltiesRegistry = _royaltiesRegistry;
        ds.daoAddress = payable(msg.sender);
        ds.daoInitialized = false;
        for (uint256 i; i < _supportedERC20Tokens.length;) {
            ds.supportedERC20Tokens[_supportedERC20Tokens[i]] = true;
            unchecked { i++; }
        }

        ds.raffleTicketAddress = _raffleTicketAddress;
        ds.vrfAddress = _vrfAddress;
    }

    function transferDAOownership(address payable _daoAddress) external {
        UniversalRaffleCore.transferDAOownership(_daoAddress);
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

    function setDepositors(uint256 raffleId, UniversalRaffleCoreTwo.AllowList[] calldata allowList) external override {
        return UniversalRaffleCoreTwo.setDepositors(raffleId, allowList);
    }

    function setAllowList(uint256 raffleId, UniversalRaffleCoreTwo.AllowList[] calldata allowList) external override {
        return UniversalRaffleCoreTwo.setAllowList(raffleId, allowList);
    }

    function toggleAllowList(uint256 raffleId) external override {
        return UniversalRaffleCoreTwo.toggleAllowList(raffleId);
    }

    function depositNFTsToRaffle(uint256 raffleId, uint256[] calldata slotIndices, UniversalRaffleCore.NFT[][] calldata tokens) external override {
        UniversalRaffleCore.depositNFTsToRaffle(raffleId, slotIndices, tokens);
    }

    function withdrawDepositedERC721(uint256 raffleId, UniversalRaffleCore.SlotIndexAndNFTIndex[] calldata slotNftIndexes) external override nonReentrant {
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

        UniversalRaffleCore.buyRaffleTicketsChecks(raffleId, amount);

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
            SafeERC20.safeTransferFrom(IERC20(raffleInfo.ERC20PurchaseToken), msg.sender, address(this), amount.mul(raffleInfo.ticketPrice));
        }

        raffle.ticketCounter += amount;
        IRaffleTickets(ds.raffleTicketAddress).mint(msg.sender, amount, raffleId);
    }

    function finalizeRaffle(uint256 raffleId, bytes32 keyHash, uint64 subscriptionId, uint16 minConf, uint32 callbackGas) external override nonReentrant {
        (
            UniversalRaffleCore.Storage storage ds,
            UniversalRaffleCore.RaffleConfig storage raffleInfo,
            UniversalRaffleCore.Raffle storage raffle
        ) = getRaffleData(raffleId);

        require(raffleId > 0 && raffleId <= ds.totalRaffles &&
                !raffle.isCanceled &&
                block.timestamp > raffleInfo.endTime && !raffle.isFinalized, "E01");

        if (raffle.ticketCounter < raffleInfo.minTicketCount) ds.raffles[raffleId].isCanceled = true;
        else {
            if (ds.unsafeVRFtesting) IRandomNumberGenerator(ds.vrfAddress).getWinnersMock(raffleId); // Testing purposes only
            else IRandomNumberGenerator(ds.vrfAddress).getWinners(raffleId, keyHash, subscriptionId, minConf, callbackGas);

            UniversalRaffleCoreTwo.calculatePaymentSplits(raffleId);
        }

        emit UniversalRaffleCoreTwo.LogRaffleFinalized(raffleId);
    }

    function setWinners(uint256 raffleId, uint256[] memory winnerIds) external {
        UniversalRaffleCore.Storage storage ds = UniversalRaffleCore.raffleStorage();
        require(msg.sender == ds.vrfAddress, "No permission");
        for (uint256 i = 1; i <= winnerIds.length;) {
            ds.raffles[raffleId].slots[i].winnerId = winnerIds[i - 1];
            ds.raffles[raffleId].slots[i].winner = IERC721(ds.raffleTicketAddress).ownerOf(winnerIds[i - 1]);
            unchecked { i++; }
        }

        ds.raffles[raffleId].isFinalized = true;
    }

    function claimERC721Rewards(uint256 raffleId, uint256 slotIndex, uint256 amount) external override nonReentrant {
        UniversalRaffleCore.claimERC721Rewards(raffleId, slotIndex, amount);
    }

    function cancelRaffle(uint256 raffleId) external override {
        return UniversalRaffleCoreTwo.cancelRaffle(raffleId);
    }

    function refundRaffleTickets(uint256 raffleId, uint256[] memory tokenIds) external override nonReentrant {
        UniversalRaffleCoreTwo.refundRaffleTickets(raffleId, tokenIds);
    }

    function distributeCapturedRaffleRevenue(uint256 raffleId) external override nonReentrant {
        UniversalRaffleCoreTwo.distributeCapturedRaffleRevenue(raffleId);
    }

    function distributeSecondarySaleFees(uint256 raffleId, uint256 slotIndex, uint256 nftSlotIndex) external override nonReentrant {
        UniversalRaffleCoreTwo.distributeSecondarySaleFees(raffleId, slotIndex, nftSlotIndex);
    }

    function distributeRoyalties(address token) external nonReentrant returns (uint256) {
        return UniversalRaffleCoreTwo.distributeRoyalties(token);
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

    function getRaffleState(uint256 raffleId) external view override returns (UniversalRaffleCore.RaffleConfig memory, UniversalRaffleCore.RaffleState memory) {
        return UniversalRaffleCore.getRaffleState(raffleId);
    }

    function getRaffleFinalize(uint256 raffleId) external view returns (bool, uint256, uint256) {
        return UniversalRaffleCore.getRaffleFinalize(raffleId);
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

    function getContractConfig() external view override returns (UniversalRaffleCore.ContractConfigByDAO memory) {
        return UniversalRaffleCore.getContractConfig();
    }
}
