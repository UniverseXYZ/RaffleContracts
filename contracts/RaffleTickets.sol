// SPDX-License-Identifier: MIT
// Written by Tim Kang <> illestrater
// Product by universe.xyz

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./UniversalRaffleCore.sol";
import "./UniversalRaffleSchema.sol";
import "./interfaces/IUniversalRaffle.sol";
import "./interfaces/IRaffleTickets.sol";
import "./HelperFunctions.sol";
import "hardhat/console.sol";
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
    uint256 raffleId = HelperFunctions.safeParseInt(HelperFunctions.substring(HelperFunctions.toString(tokenId), bytes(HelperFunctions.toString(tokenId)).length - 8, bytes(HelperFunctions.toString(tokenId)).length - 7));
    // UniversalRaffleCore.RaffleConfig memory raffle = IUniversalRaffle(universalRaffleAddress).getRaffleConfig(raffleId);
    (UniversalRaffleSchema.RaffleConfig memory raffle, UniversalRaffleSchema.RaffleState memory raffleState) = IUniversalRaffle(universalRaffleAddress).getRaffleState(raffleId);
    uint256 ticketId = tokenId - (raffleId * 10000000);

    string memory claim;
    string memory time;
    if (block.timestamp > raffle.endTime) {
      if (raffleState.isFinalized) claim = 'Void';
      else claim = 'Pending Results';
      time = 'Ended';
    } else {
      claim = 'Awaiting Results';
      time = 'Pre-Raffle';
    }

    for (uint256 i = 0; i < raffle.totalSlots; i++) {
      UniversalRaffleSchema.SlotInfo memory slot = IUniversalRaffle(universalRaffleAddress).getSlotInfo(raffleId, i + 1);
      if (slot.winnerId == tokenId) {
        if (slot.depositedNFTCounter == slot.withdrawnNFTCounter) claim = 'Prize Claimed';
        else if (slot.withdrawnNFTCounter > 0) claim = 'Partially Claimed';
        else if (slot.withdrawnNFTCounter == 0) claim = 'Winner Unclaimed';
      }
    }

    string memory image;
    if (keccak256(abi.encodePacked(raffle.raffleImageURL)) != keccak256(abi.encodePacked(''))) {
      image = string(abi.encodePacked(
        '<image href="',
        raffle.raffleImageURL,
        '" x="630" y="100" height="130" width="130" />'
      ));
    }

    string memory encoded = string(
      abi.encodePacked(
        'data:application/json;base64,',
        Base64.encode(
          bytes(
            abi.encodePacked(
              '{"name":"',
              'Raffle Ticket #',
              HelperFunctions.toString(ticketId),
              '", "description":"',
              'Raffle ticket NFT for ',
              raffle.raffleName,
              '", "image":"',
              'data:image/svg+xml;base64,',
              Base64.encode(
                bytes(
                  abi.encodePacked(
                    '<svg width="500" height="500" viewBox="0 0 800 360" xmlns="http://www.w3.org/2000/svg"><defs><filter id="noise"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="10" stitchTiles="nostitch" /></filter><linearGradient id="golden-grad"><stop offset="0%" stop-color="#BF953F"><animate attributeName="stop-color" values="#BF953F;#FCF6BA;#BF953F" dur="5s" repeatCount="indefinite" /></stop><stop offset="20%" stop-color="#FCF6BA"><animate attributeName="stop-color" values="#FCF6BA;#BF953F;#FCF6BA" dur="6s" repeatCount="indefinite" /></stop><stop offset="60%" stop-color="#BF953F"><animate attributeName="stop-color" values="#BF953F;#FCF6BA;#BF953F" dur="4s" repeatCount="indefinite" /></stop><stop offset="80%" stop-color="#FCF6BA"><animate attributeName="stop-color" values="#FCF6BA;#BF953F;#FCF6BA" dur="6s" repeatCount="indefinite" /></stop><stop offset="100%" stop-color="#BF953F"><animate attributeName="stop-color" values="#BF953F;#FCF6BA;#BF953F" dur="5s" repeatCount="indefinite" /></stop></linearGradient><clipPath id="ticket"><path d="M 0 0 L 10 10 0 20 10 30 0 40 10 50 0 60 10 70 0 80 10 90 0 100 10 110 0 120 10 130 0 140 10 150 0 160 10 170 0 180 10 190 0 200 10 210 0 220 10 230 0 240 10 250 0 260 10 270 0 280 10 290 0 300 10 310 0 320 10 330 0 340 10 350 0 360 H 800 L 790 350 800 340 790 330 800 320 790 310 800 300 790 290 800 280 790 270 800 260 790 250 800 240 790 230 800 220 790 210 800 200 790 190 800 180 790 170 800 160 790 150 800 140 790 130 800 120 790 110 800 100 790 90 800 80 790 70 800 60 790 50 800 40 790 30 800 20 790 10 800 0 Z" /></clipPath></defs><rect x="0" y="0" width="800" height="360" clip-path="url(#ticket)" fill="url(#golden-grad)" /><g><line x1="20" y1="80" x2="780" y2="80" stroke-width="5" stroke="#000" /><line x1="20" y1="250" x2="780" y2="250" stroke-width="5" stroke="#000" /></g><g><text x="40" y="60" font-family="Courier New, monospace" font-weight="700" font-size="40">Raffle Ticket</text>',
                    image,
                    '<text x="40" y="120" font-family="Courier New, monospace" font-weight="700" font-size="20">',
                    raffle.raffleName,
                    '</text><text x="80" y="150" font-family="Courier New, monospace" font-size="16">Raffler: 0x',
                    HelperFunctions.toAsciiString(raffle.raffler),
                    '</text><text x="80" y="180" font-family="Courier New, monospace" font-size="16">Raffle ID: ',
                    HelperFunctions.toString(raffleId),
                    '</text><text x="80" y="210" font-family="Courier New, monospace" font-size="16">Tickets Sold: ',
                    HelperFunctions.toString(raffleState.ticketCounter),
                    '</text><text x="50" y="290" font-family="Courier New, monospace" font-size="20">Ticket #</text><text x="47" y="330" font-family="Courier New, monospace" font-size="30">',
                    HelperFunctions.toString(ticketId),
                    '</text><text x="230" y="290" font-family="Courier New, monospace" font-size="20">Time</text><text x="230" y="330" font-family="Courier New, monospace" font-size="30">',
                    time,
                    '</text><text x="450" y="290" font-family="Courier New, monospace" font-size="20">Claim</text><text x="450" y="330" font-family="Courier New, monospace" font-size="30">',
                    claim,
                    '</text></g><rect x="0" y="0" width="800" height="360" clip-path="url(#ticket)" filter="url(#noise)" opacity=".4" /></svg>'
                  )
                )
              ),
              '"}'
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