### Overview

- A raffler can deposit NFTs into multiple slots of winners
- A slot can have multiple NFTs
- People can purchase multiple raffle tickets represented as NFTs
- Upon raffle completion, Chainlink VRF is used to select random winners
- Winners can then claim their prize if they are selected

### Raffle House Parameters (DAO Control)
- Number of slots number of slots per raffle
- Maximum NFTs per slot
- Collection royalties
- DAO Address
- Contract address of raffle ticket NFTs
- Chainlink VRF contract address
- List of supported ERC20 tokens used for raffles
- Royalty registry


### Raffle Parameters (Raffler control)
- ERC20 token used for raffle
- Start time of raffle (people can purchase raffle tickets)
- End time of raffle (end raffle ticket purchase period)
- Maximum tickets that can exist
- Minimum ticketes that must be purchased to proceed, else raffle canceled
- Price per raffle ticket
- Number of slots


### Flow

## 1. Raffle creation (raffler)
- Raffler creates a new raffle with specified number of slots / winners
- Raffler defines start/end time, max/min tickets, price per ticket, and ERC20 token used OR Ether

## 2. NFT Deposit
- Raffler deposits NFTs in each slot
- Raffler can cancel/reconfigure up until start time

## 3. Raffle starts
- People can bulk purchase raffle tickets and receive NFTs
- People cannot refund their raffle ticket unless raffle is canceled

## 4. Raffle ends
- Anyone can call finalizeRaffle function after raffle end time
- Raffle is canceled if minimum tickets are not purchased
- Chainlink VRF is used to select random winners and stores winner address data for each slot

## 5. Payout claims
- Slot winners can withdraw the NFTs from their respective slots
- Raffler can withdraw the proceeds paid for raffle tickets
- If raffle was canceled, NFT ticket owners can withdraw refund