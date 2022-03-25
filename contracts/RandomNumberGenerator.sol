// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Forked from Universe Auction House by Stan
// Product by universe.xyz

pragma solidity 0.8.11;

import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "./interfaces/IRandomNumberGenerator.sol";
import "./interfaces/IUniversalRaffle.sol";
import "./UniversalRaffleCore.sol";
import "./RaffleTickets.sol";
import "hardhat/console.sol";

contract RandomNumberGenerator is IRandomNumberGenerator, VRFConsumerBaseV2 {
    address private creationAddress;
    address public universalRaffleAddress;
    RaffleTickets public raffleTickets;
    bool public initialized = false;

    mapping(uint256 => uint256) public vrfToRaffleId;

    // Chainlink Parameters
    VRFCoordinatorV2Interface COORDINATOR;
    LinkTokenInterface LINKTOKEN;
    bytes32 keyHash;
    uint64 subscriptionId;

    constructor(
      address _vrfCoordinator,
      address _linkToken,
      bytes32 _keyHash,
      uint64 _subscriptionId,
      address _raffleTicketAddress
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        creationAddress = msg.sender;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        LINKTOKEN = LinkTokenInterface(_linkToken);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;

        raffleTickets = RaffleTickets(_raffleTicketAddress);
    }

    modifier onlyDeployer() {
      require(msg.sender == creationAddress, "Not allowed");
      _;
    }

    modifier onlyRaffleContract() {
      require(msg.sender == universalRaffleAddress, "Not allowed");
      _;
    }

    function initVRF(address _contractAddress) external override onlyDeployer() {
      require(!initialized, "Already initialized");
      universalRaffleAddress = _contractAddress;
    }

    function getWinners(uint256 raffleId, bytes32 _keyHash, uint64 _subscriptionId, uint16 _minConf, uint32 _callbackGas) external override onlyRaffleContract() {
      (UniversalRaffleCore.RaffleConfig memory raffle,) = IUniversalRaffle(universalRaffleAddress).getRaffleState(raffleId);
      uint256 requestId = COORDINATOR.requestRandomWords(
          keccak256(abi.encodePacked(_keyHash)) != keccak256(abi.encodePacked('0x0000000000000000000000000000000000000000000000000000000000000000')) ? _keyHash : keyHash,
          _subscriptionId > 0 ? _subscriptionId : subscriptionId,
          _minConf > 0 ? _minConf : 3,
          _callbackGas > 0 ? _callbackGas : 300000,
          raffle.totalSlots
      );

      vrfToRaffleId[requestId] = raffleId;
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 raffleId = vrfToRaffleId[requestId];

        (UniversalRaffleCore.RaffleConfig memory raffle, UniversalRaffleCore.RaffleState memory raffleState) = IUniversalRaffle(universalRaffleAddress).getRaffleState(raffleId);
        uint256 totalSlots = raffle.totalSlots;
        uint256 ticketCounter = raffleState.ticketCounter;

        require (true, 'Already finalized');

        uint256[] memory winnerIds = new uint256[](totalSlots);
        address[] memory winners = new address[](totalSlots);
        for (uint32 i = 0; i < totalSlots; i++) {
          uint256 winnerId = (raffleId * 10000000) + (randomWords[i] % ticketCounter) + 1;

          bool stored = false;
          while (!stored) {
            for (uint32 j = 0; j < winnerIds.length; j++) {
              if (winnerIds[j] == winnerId) {
                if (((randomWords[i] % ticketCounter) + j + 1) == ticketCounter) {
                  winnerId = (raffleId * 10000000) + 1;
                } else winnerId++;
              } else {
                stored = true;
              }
            }
          }

          winnerIds[i] = winnerId;
          winners[i] = raffleTickets.ownerOf(winnerId);
        }

        IUniversalRaffle(universalRaffleAddress).setWinners(raffleId, winnerIds, winners);
    }

    // Used for testing purposes only
    function getWinnersMock(uint256 raffleId) external override onlyRaffleContract() {
        (UniversalRaffleCore.RaffleConfig memory raffle, UniversalRaffleCore.RaffleState memory raffleState) = IUniversalRaffle(universalRaffleAddress).getRaffleState(raffleId);
        uint256 totalSlots = raffle.totalSlots;
        uint256 ticketCounter = raffleState.ticketCounter;

        uint256[] memory randomWords = new uint256[](totalSlots);
        for (uint256 i = 0; i < totalSlots; i++) {
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, raffleId + i)));
            randomWords[i] = randomNumber;
        }

        uint256[] memory winnerIds = new uint256[](totalSlots);
        address[] memory winners = new address[](totalSlots);
        for (uint32 i = 0; i < totalSlots; i++) {
          uint256 winnerId = (raffleId * 10000000) + (randomWords[i] % ticketCounter) + 1;

          bool stored = false;
          while (!stored) {
            for (uint32 j = 0; j < winnerIds.length; j++) {
              if (winnerIds[j] == winnerId) {
                if (((randomWords[i] % ticketCounter) + j + 1) == ticketCounter) {
                  winnerId = (raffleId * 10000000) + 1;
                } else winnerId++;
              } else {
                stored = true;
              }
            }
          }

          winnerIds[i] = winnerId;
          winners[i] = raffleTickets.ownerOf(winnerId);
        }

        IUniversalRaffle(universalRaffleAddress).setWinners(raffleId, winnerIds, winners);
    }
}