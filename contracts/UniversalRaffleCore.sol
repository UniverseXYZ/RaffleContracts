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
import "./UniversalRaffleSchema.sol";

library UniversalRaffleCore {
    using SafeMath for uint256;

    bytes32 constant STORAGE_POSITION = keccak256("com.universe.raffle.storage");

    function raffleStorage() internal pure returns (UniversalRaffleSchema.Storage storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
        ds.slot := position
        }
    }

    modifier onlyRaffleSetup(uint256 raffleId) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        require(raffleId > 0 &&
                raffleId <= ds.totalRaffles &&
                ds.raffleConfigs[raffleId].startTime > block.timestamp &&
                !ds.raffles[raffleId].isCanceled, "E01");
        _;
    }

    modifier onlyDAO() {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        require(msg.sender == ds.daoAddress, "E07");
        _;
    }

    function transferDAOownership(address payable _daoAddress) external onlyDAO {
        UniversalRaffleSchema.Storage storage ds = UniversalRaffleCore.raffleStorage();
        ds.daoAddress = _daoAddress;
        ds.daoInitialized = true;
    }

    function configureRaffle(UniversalRaffleSchema.RaffleConfig calldata config, uint256 existingRaffleId) external returns (uint256) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        uint256 currentTime = block.timestamp;

        require(currentTime < config.startTime && config.startTime < config.endTime, 'Out of time configuration');
        require(config.totalSlots > 0 && config.totalSlots <= ds.maxNumberOfSlotsPerRaffle, 'Incorrect slots');
        require(config.ERC20PurchaseToken == address(0) || ds.supportedERC20Tokens[config.ERC20PurchaseToken], 'Token not allowed');
        require(config.minTicketCount > 1 && config.maxTicketCount >= config.minTicketCount,"Wrong ticket count");

        uint256 raffleId;
        if (existingRaffleId > 0) {
            raffleId = existingRaffleId;
            require(ds.raffleConfigs[raffleId].raffler == msg.sender && ds.raffleConfigs[raffleId].startTime > currentTime, "No permission");
            emit UniversalRaffleSchema.LogRaffleEdited(raffleId, msg.sender, config.raffleName);
        } else {
            ds.totalRaffles = ds.totalRaffles + 1;
            raffleId = ds.totalRaffles;

            ds.raffleConfigs[raffleId].raffler = msg.sender;
            ds.raffleConfigs[raffleId].totalSlots = config.totalSlots;

            emit UniversalRaffleSchema.LogRaffleCreated(raffleId, msg.sender, config.raffleName);
        }

        ds.raffleConfigs[raffleId].ERC20PurchaseToken = config.ERC20PurchaseToken;
        ds.raffleConfigs[raffleId].startTime = config.startTime;
        ds.raffleConfigs[raffleId].endTime = config.endTime;
        ds.raffleConfigs[raffleId].maxTicketCount = config.maxTicketCount;
        ds.raffleConfigs[raffleId].minTicketCount = config.minTicketCount;
        ds.raffleConfigs[raffleId].ticketPrice = config.ticketPrice;
        ds.raffleConfigs[raffleId].raffleName = config.raffleName;
        ds.raffleConfigs[raffleId].ticketColorOne = config.ticketColorOne;
        ds.raffleConfigs[raffleId].ticketColorTwo = config.ticketColorTwo;

        uint256 checkSum = 0;
        delete ds.raffleConfigs[raffleId].paymentSplits;
        for (uint256 k; k < config.paymentSplits.length;) {
            require(config.paymentSplits[k].recipient != address(0) && config.paymentSplits[k].value != 0, "Bad splits data");
            checkSum += config.paymentSplits[k].value;
            ds.raffleConfigs[raffleId].paymentSplits.push(config.paymentSplits[k]);
            unchecked { k++; }
        }
        require(checkSum < 10000, "Splits should be less than 100%");

        return raffleId;
    }

    function depositNFTsToRaffle(
        uint256 raffleId,
        uint256[] calldata slotIndices,
        UniversalRaffleSchema.NFT[][] calldata tokens
    ) external onlyRaffleSetup(raffleId) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.RaffleConfig storage raffle = ds.raffleConfigs[raffleId];

        require(
            slotIndices.length <= raffle.totalSlots &&
                slotIndices.length <= 10 &&
                slotIndices.length == tokens.length,
            "Incorrect slots"
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
        UniversalRaffleSchema.NFT[] calldata tokens
    ) internal returns (uint256[] memory) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];
        UniversalRaffleSchema.RaffleConfig storage raffleConfig = ds.raffleConfigs[raffleId];

        require(msg.sender == raffleConfig.raffler || raffle.depositors[msg.sender], 'No permission');
        require(raffleConfig.totalSlots >= slotIndex && slotIndex > 0, 'Incorrect slots');
        require(tokens.length <= 40 && raffle.slots[slotIndex].depositedNFTCounter + tokens.length <= ds.nftSlotLimit, "Too many NFTs");

        // Ensure previous slot has depoited NFTs, so there is no case where there is an empty slot between non-empty slots
        if (slotIndex > 1) require(raffle.slots[slotIndex - 1].depositedNFTCounter > 0, "Previous slot empty");

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
        UniversalRaffleSchema.Storage storage ds = raffleStorage();

        (LibPart.Part[] memory nftRoyalties,) = ds.royaltiesRegistry.getRoyalties(tokenAddress, tokenId);

        address[] memory feesAddress = new address[](nftRoyalties.length);
        uint96[] memory feesValue = new uint96[](nftRoyalties.length);
        for (uint256 i; i < nftRoyalties.length && i < 5;) {
            feesAddress[i] = nftRoyalties[i].account;
            feesValue[i] = nftRoyalties[i].value;
            unchecked { i++; }
        }

        IERC721(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenId);

        ds.raffles[raffleId].slots[slotIndex].depositedNFTs[nftSlotIndex] = UniversalRaffleSchema.DepositedNFT({
            tokenId: tokenId,
            tokenAddress: tokenAddress,
            depositor: msg.sender,
            hasSecondarySaleFees: nftRoyalties.length > 0,
            feesPaid: false,
            feesAddress: feesAddress,
            feesValue: feesValue
        });

        emit UniversalRaffleSchema.LogERC721Deposit(
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
        UniversalRaffleSchema.SlotIndexAndNFTIndex[] calldata slotNftIndexes
    ) external {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];

        require(raffleId > 0 && raffleId <= ds.totalRaffles, 'Does not exist');
        require(ds.raffles[raffleId].isCanceled, "Raffle must be canceled");

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
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.DepositedNFT memory nftForWithdrawal = ds.raffles[raffleId].slots[slotIndex].depositedNFTs[
            nftSlotIndex
        ];

        require(msg.sender == nftForWithdrawal.depositor, "No permission");
        delete ds.raffles[raffleId].slots[slotIndex].depositedNFTs[nftSlotIndex];

        emit UniversalRaffleSchema.LogERC721Withdrawal(
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
        uint256 raffleId,
        uint256 slotIndex,
        uint256 amount
    ) external {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();

        UniversalRaffleSchema.Raffle storage raffle = ds.raffles[raffleId];
        UniversalRaffleSchema.Slot storage winningSlot = raffle.slots[slotIndex];

        uint256 totalWithdrawn = winningSlot.withdrawnNFTCounter;

        require(raffle.isFinalized, 'Must finalize raffle');
        require(winningSlot.winner == msg.sender, 'No permission');
        require(amount <= 40 && amount <= winningSlot.depositedNFTCounter - totalWithdrawn, "Too many NFTs");

        emit UniversalRaffleSchema.LogERC721RewardsClaim(msg.sender, raffleId, slotIndex, amount);

        raffle.withdrawnNFTCounter += amount;
        raffle.slots[slotIndex].withdrawnNFTCounter = winningSlot.withdrawnNFTCounter += amount;
        for (uint256 i = totalWithdrawn; i < amount + totalWithdrawn;) {
            UniversalRaffleSchema.DepositedNFT memory nftForWithdrawal = winningSlot.depositedNFTs[i + 1];

            IERC721(nftForWithdrawal.tokenAddress).safeTransferFrom(
                address(this),
                msg.sender,
                nftForWithdrawal.tokenId
            );

            unchecked { i++; }
        }
    }

    function setRaffleConfigValue(uint256 configType, uint256 _value) external onlyDAO returns (uint256) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();

        if (configType == 0) ds.maxNumberOfSlotsPerRaffle = _value;
        else if (configType == 1) ds.maxBulkPurchaseCount = _value;
        else if (configType == 2) ds.nftSlotLimit = _value;
        else if (configType == 3) ds.royaltyFeeBps = _value;

        return _value;
    }

    function setRoyaltiesRegistry(IRoyaltiesProvider _royaltiesRegistry) external onlyDAO returns (IRoyaltiesProvider) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        ds.royaltiesRegistry = _royaltiesRegistry;
        return ds.royaltiesRegistry;
    }

    function setSupportedERC20Tokens(address erc20token, bool value) external onlyDAO returns (address, bool) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        ds.supportedERC20Tokens[erc20token] = value;
        return (erc20token, value);
    }

    function getRaffleState(uint256 raffleId) external view returns (UniversalRaffleSchema.RaffleConfig memory, UniversalRaffleSchema.RaffleState memory)
    {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        return (ds.raffleConfigs[raffleId], UniversalRaffleSchema.RaffleState(
            ds.raffles[raffleId].ticketCounter,
            ds.raffles[raffleId].depositedNFTCounter,
            ds.raffles[raffleId].withdrawnNFTCounter,
            ds.raffles[raffleId].useAllowList,
            ds.raffles[raffleId].isSetup,
            ds.raffles[raffleId].isCanceled,
            ds.raffles[raffleId].isFinalized,
            ds.raffles[raffleId].revenuePaid
        ));
    }

    function getRaffleFinalize(uint256 raffleId) external view returns (bool, uint256, uint256) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        return (ds.raffles[raffleId].isFinalized, ds.raffleConfigs[raffleId].totalSlots, ds.raffles[raffleId].ticketCounter);
    }

    function getDepositorList(uint256 raffleId, address participant) external view returns (bool) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        return ds.raffles[raffleId].depositors[participant];
    }

    function getAllowList(uint256 raffleId, address participant) external view returns (uint256) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        return ds.raffles[raffleId].allowList[participant];
    }

    function getDepositedNftsInSlot(uint256 raffleId, uint256 slotIndex) external view returns (UniversalRaffleSchema.DepositedNFT[] memory) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        uint256 nftsInSlot = ds.raffles[raffleId].slots[slotIndex].depositedNFTCounter;

        UniversalRaffleSchema.DepositedNFT[] memory nfts = new UniversalRaffleSchema.DepositedNFT[](nftsInSlot);

        for (uint256 i; i < nftsInSlot;) {
            nfts[i] = ds.raffles[raffleId].slots[slotIndex].depositedNFTs[i + 1];
            unchecked { i++; }
        }
        return nfts;
    }

    function getSlotInfo(uint256 raffleId, uint256 slotIndex) external view returns (UniversalRaffleSchema.SlotInfo memory) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();
        UniversalRaffleSchema.Slot storage slot = ds.raffles[raffleId].slots[slotIndex];
        UniversalRaffleSchema.SlotInfo memory slotInfo = UniversalRaffleSchema.SlotInfo(
            slot.depositedNFTCounter,
            slot.withdrawnNFTCounter,
            slot.winnerId,
            slot.winner
        );
        return slotInfo;
    }

    function getContractConfig() external view returns (UniversalRaffleSchema.ContractConfigByDAO memory) {
        UniversalRaffleSchema.Storage storage ds = raffleStorage();

        return UniversalRaffleSchema.ContractConfigByDAO(
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
