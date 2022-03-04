// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Product by universe.xyz

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./UniversalRaffleCore.sol";
import "./interfaces/IUniversalRaffle.sol";
import "./interfaces/IRaffleTickets.sol";
import 'base64-sol/base64.sol';

contract RaffleTickets is IRaffleTickets, ERC721 {
  address private creationAddress;
  address public universalRaffleAddress;
  bool public initialized = false;
  uint256 mintedTickets = 0;

  mapping(uint256 => uint32) ticketCounter;

  constructor() ERC721("Raffle Tickets", "RAFFLE") {
    creationAddress = msg.sender;
  }

  modifier onlyDeployer() {
    require(msg.sender == creationAddress, "Not allowed");
    _;
  }

  modifier onlyRaffleContract() {
    require(msg.sender == universalRaffleAddress, "Not allowed");
    _;
  }

  function initRaffleTickets(address _contractAddress) public onlyDeployer() {
    require(!initialized, "Already initialized");
    universalRaffleAddress = _contractAddress;
  }

  function mint(address to, uint256 amount, uint256 raffleId) public onlyRaffleContract() {
    uint32 raffleTokenIdBase = uint32((raffleId) * 10000000);
    for (uint32 i = 1; i <= amount; i++) {
      _mint(to, raffleTokenIdBase + ticketCounter[raffleId] + i);
    }

    ticketCounter[raffleId] += uint32(amount);
    mintedTickets++;
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    UniversalRaffleCore.RaffleConfig memory raffle = IUniversalRaffle(universalRaffleAddress).getRaffleConfig(1);
    UniversalRaffleCore.RaffleState memory raffleState = IUniversalRaffle(universalRaffleAddress).getRaffleState(1);

    string memory encoded = string(
      abi.encodePacked(
        'data:application/json;base64,',
        Base64.encode(
          bytes(
            abi.encodePacked(
              '{"name":"',
              'test',
              '", "description":"',
              'yooo',
              '}'
            )
          )
        )
      )
    );

    return encoded;
  }

  function totalSupply() public view returns (uint256) {
    return mintedTickets;
  }

  function raffleTicketCounter(uint256 raffleId) public view returns (uint256) {
    return ticketCounter[raffleId];
  }
}