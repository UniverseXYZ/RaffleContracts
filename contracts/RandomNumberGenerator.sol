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

    function initVRF(address _contractAddress) public override onlyDeployer() {
      require(!initialized, "Already initialized");
      universalRaffleAddress = _contractAddress;
    }

    function getWinners(uint256 raffleId) public override onlyRaffleContract() {
      uint256 requestId = COORDINATOR.requestRandomWords(
          keyHash,
          subscriptionId,
          3,
          300000,
          IUniversalRaffle(universalRaffleAddress).getRaffleConfig(raffleId).totalSlots
      );

      vrfToRaffleId[requestId] = raffleId;
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 raffleId = vrfToRaffleId[requestId];

        UniversalRaffleCore.RaffleConfig memory raffle = IUniversalRaffle(universalRaffleAddress).getRaffleConfig(raffleId);
        UniversalRaffleCore.RaffleState memory raffleState = IUniversalRaffle(universalRaffleAddress).getRaffleState(raffleId);

        address[] memory winners = new address[](raffle.totalSlots);
        for (uint32 i = 0; i < raffle.totalSlots; i++) {
            winners[i] = raffleTickets.ownerOf(
              (raffleId * 10000000) +
              (randomWords[i] % raffleState.ticketCounter) + 1
            );
        }

        IUniversalRaffle(universalRaffleAddress).setWinners(raffleId, winners);
    }

    // Used for testing purposes only
    function getWinnersMock(uint256 raffleId) public override onlyRaffleContract() {
        UniversalRaffleCore.RaffleConfig memory raffle = IUniversalRaffle(universalRaffleAddress).getRaffleConfig(raffleId);
        UniversalRaffleCore.RaffleState memory raffleState = IUniversalRaffle(universalRaffleAddress).getRaffleState(raffleId);

        uint256[] memory words = new uint256[](raffle.totalSlots);
        for (uint256 i = 0; i < raffle.totalSlots; i++) {
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, raffleId + i)));
            words[i] = randomNumber;
        }

        address[] memory winners = new address[](raffle.totalSlots);
        for (uint32 i = 0; i < raffle.totalSlots; i++) {
            winners[i] = raffleTickets.ownerOf(
              (raffleId * 10000000) +
              (words[i] % raffleState.ticketCounter) + 1
            );
        }

        IUniversalRaffle(universalRaffleAddress).setWinners(raffleId, winners);
    }
}