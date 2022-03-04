const { expect } = require("chai");
const { ethers } = require("hardhat");
const { waffle, upgrades } = require('hardhat');
const { loadFixture } = waffle;

const vrfCoordinator = '0x6168499c0cFfCaCD319c818142124B7A15E857ab';
const link = '0x01BE23585060835E02B77ef475b0Cc51aA1e0709';
const keyHash = '0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc';
const subscriptionId = 677;

async function findSigner(address) {
  const signers = await ethers.getSigners();
  let found = false;
  let signer;
  let counter = 0;
  while (!found) {
    if (!signers[counter]) found = true;
    if (signers[counter] && signers[counter].address == address) {
      signer = signers[counter];
      found = true;
    }

    else counter++;
  }

  return signer ? signer : false;
}

describe("Raffle Core Tests", async function () {
  const currentTime = Math.round((new Date()).getTime() / 1000);

  let purchaseToken;
  const zeroAddress = '0x0000000000000000000000000000000000000000';
  const startTime = currentTime + 100;
  const endTime = currentTime + 500;
  const maxTicketCount = 1000;
  const minTicketCount = 100;
  const tokenPrice = ethers.utils.parseEther("3.0");
  const totalSlots = 10;
  const paymentSplits = [];

  const TEST_VRF = true;
  const MAX_NUMBER_SLOTS = 2000;
  const MAX_BULK_PURCHASE = 50;
  const NFT_SLOT_LIMIT = 100
  const ROYALTY_FEE_BPS = 0;

  async function deployContracts() {
    const [owner, addr1] = await ethers.getSigners();

    const MockNFT = await ethers.getContractFactory('MockNFT');
    const MockToken = await ethers.getContractFactory('MockToken');
    const mockNFT = await MockNFT.deploy();
    const mockToken = await MockToken.deploy(ethers.utils.parseEther("10000"));
    purchaseToken = mockToken.address;

    const RaffleTicketsFactory = await hre.ethers.getContractFactory("RaffleTickets");
    const RaffleTickets = await RaffleTicketsFactory.deploy();
    await RaffleTickets.deployed();

    const VRF = await hre.ethers.getContractFactory("RandomNumberGenerator");
    const VRFInstance = await VRF.deploy(
      vrfCoordinator, link, keyHash, subscriptionId, RaffleTickets.address
    );
    await VRFInstance.deployed();

    const MockRoyaltiesRegistry =  await ethers.getContractFactory('MockRoyaltiesRegistry');
    const mockRoyaltiesRegistry = await upgrades.deployProxy(MockRoyaltiesRegistry, [], {initializer: "__RoyaltiesRegistry_init"});

    const UniversalRaffleCore = await hre.ethers.getContractFactory("UniversalRaffleCore");
    const CoreInstance = await UniversalRaffleCore.deploy();
    await CoreInstance.deployed();

    const UniversalRaffleFactory = await ethers.getContractFactory("UniversalRaffle",
    {
      libraries: {
        UniversalRaffleCore: CoreInstance.address
      }
    });

    const UniversalRaffle = await UniversalRaffleFactory.deploy(
      TEST_VRF,
      MAX_NUMBER_SLOTS,
      MAX_BULK_PURCHASE,
      NFT_SLOT_LIMIT,
      ROYALTY_FEE_BPS,
      owner.address,
      RaffleTickets.address,
      VRFInstance.address,
      [mockToken.address],
      mockRoyaltiesRegistry.address
    );

    await UniversalRaffle.deployed();

    await RaffleTickets.initRaffleTickets(UniversalRaffle.address);
    await VRFInstance.initVRF(UniversalRaffle.address);

    return { UniversalRaffle, RaffleTickets, mockNFT, mockToken };
  };

  async function launchRaffles() {
    const [owner] = await ethers.getSigners();

    const { UniversalRaffle, RaffleTickets, mockNFT, mockToken } = await loadFixture(deployContracts);

    await UniversalRaffle.createRaffle([
      owner.address,
      zeroAddress,
      startTime,
      endTime,
      maxTicketCount,
      minTicketCount,
      tokenPrice,
      totalSlots,
      paymentSplits,
    ]);

    await UniversalRaffle.createRaffle([
      owner.address,
      purchaseToken,
      startTime,
      endTime,
      maxTicketCount,
      minTicketCount,
      tokenPrice,
      totalSlots,
      paymentSplits,
    ]);

    return { UniversalRaffle, RaffleTickets, mockNFT, mockToken };
  }

  async function raffleWithNFTs() {
    const [owner] = await ethers.getSigners();

    const { UniversalRaffle, RaffleTickets, mockNFT, mockToken } = await loadFixture(launchRaffles);

    let counter = 0;
    while (counter < 30) {
      await mockNFT.mint(owner.address, 'nftURI');
      counter++;
    }

    const slotIndexes = [];
    const NFTs = [];
    for (let i = 1; i <= 10; i++) {
      slotIndexes.push(i);
      NFTs.push([[i, mockNFT.address]]);
    }

    NFTs[1].push([11, mockNFT.address]);

    await mockNFT.setApprovalForAll(UniversalRaffle.address, true);
    await UniversalRaffle.batchDepositToRaffle(1, slotIndexes, NFTs);

    await UniversalRaffle.depositERC721(2, 1, [[12, mockNFT.address]]);
    await UniversalRaffle.depositERC721(2, 2, [[13, mockNFT.address]]);

    return { UniversalRaffle, RaffleTickets, mockNFT, mockToken };
  }

  it('should create ERC20 raffle', async () => {
    const [owner] = await ethers.getSigners();
    const { UniversalRaffle } = await loadFixture(launchRaffles);

    const raffleInfo = await UniversalRaffle.getRaffleConfig(1);
    expect(raffleInfo[0]).to.equal(owner.address);
    expect(raffleInfo[1]).to.equal(zeroAddress);
    expect(raffleInfo[2].toNumber()).to.equal(startTime);
    expect(raffleInfo[3].toNumber()).to.equal(endTime);
    expect(raffleInfo[4].toNumber()).to.equal(maxTicketCount);
    expect(raffleInfo[5].toNumber()).to.equal(minTicketCount);
    expect(raffleInfo[6].toString()).to.equal(tokenPrice.toString());
    expect(raffleInfo[7]).to.equal(totalSlots);
    expect(JSON.stringify(raffleInfo[8])).to.equal(JSON.stringify(paymentSplits));
  })

  it('should create ETH raffle', async () => {
    const [owner] = await ethers.getSigners();
    const { UniversalRaffle } = await loadFixture(launchRaffles);

    const raffleInfo = await UniversalRaffle.getRaffleConfig(1);
    expect(raffleInfo[0]).to.equal(owner.address);
    expect(raffleInfo[1]).to.equal(zeroAddress);
    expect(raffleInfo[2].toNumber()).to.equal(startTime);
    expect(raffleInfo[3].toNumber()).to.equal(endTime);
    expect(raffleInfo[4].toNumber()).to.equal(maxTicketCount);
    expect(raffleInfo[5].toNumber()).to.equal(minTicketCount);
    expect(raffleInfo[6].toString()).to.equal(tokenPrice.toString());
    expect(raffleInfo[7]).to.equal(totalSlots);
    expect(JSON.stringify(raffleInfo[8])).to.equal(JSON.stringify(paymentSplits));
  })

  it('should purchase ERC20 raffle tickets', async () => {
    const [owner] = await ethers.getSigners();
    const { UniversalRaffle, RaffleTickets, mockToken } = await loadFixture(raffleWithNFTs);

    const startTime = currentTime + 100;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    const raffleId = 2;
    const buyAmount = 20;
    await mockToken.approve(UniversalRaffle.address, tokenPrice.mul(buyAmount));
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount);

    await mockToken.approve(UniversalRaffle.address, tokenPrice.mul(51));
    await expect(UniversalRaffle.buyRaffleTickets(raffleId, 51)).to.be.reverted;

    const tokenId = raffleId * 10000000 + 1;
    expect(await RaffleTickets.ownerOf(tokenId)).to.equal(owner.address);
    expect(await RaffleTickets.balanceOf(owner.address)).to.equal(20);
  })

  it('should purchase ETH raffle tickets', async () => {
    const [owner] = await ethers.getSigners();
    const { UniversalRaffle, RaffleTickets } = await loadFixture(raffleWithNFTs);

    const startTime = currentTime + 100;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    const raffleId = 1;
    const buyAmount = 20;
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount * 2) });

    await expect(UniversalRaffle.buyRaffleTickets(raffleId, 5, { value: tokenPrice.mul(2) })).to.be.reverted;
    await expect(UniversalRaffle.buyRaffleTickets(raffleId, 51, { value: tokenPrice.mul(51) })).to.be.reverted;

    const tokenId = raffleId * 10000000 + 40;
    expect(await RaffleTickets.ownerOf(tokenId)).to.equal(owner.address);
    expect(await RaffleTickets.balanceOf(owner.address)).to.equal(40);
  })

  it('should cancel raffle', async () => {
    const { UniversalRaffle, RaffleTickets } = await loadFixture(raffleWithNFTs);
    const raffleId = 1;

    await UniversalRaffle.cancelRaffle(raffleId);
  })

  it('should refund raffle tickets', async () => {
    const [owner] = await ethers.getSigners();
    const { UniversalRaffle, mockToken } = await loadFixture(raffleWithNFTs);

    const startTime = currentTime + 100;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    const raffleId = 2;
    const buyAmount = 20;
    const tokenId = raffleId * 10000000 + 1;
    await mockToken.approve(UniversalRaffle.address, tokenPrice.mul(buyAmount));
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount);
    await expect(UniversalRaffle.refundRaffleTickets(raffleId, [tokenId])).to.be.reverted;

    const closeTime = currentTime + 1000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [closeTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.finalizeRaffle(raffleId);

    let config = await UniversalRaffle.getRaffleState(raffleId);
    expect(config[4]).to.equal(true);

    let contractBalancePre = await mockToken.balanceOf(UniversalRaffle.address);
    let ownerBalancePre = await mockToken.balanceOf(owner.address);

    await UniversalRaffle.refundRaffleTickets(raffleId, [tokenId]);

    let contractBalancePost = await mockToken.balanceOf(UniversalRaffle.address);
    let ownerBalancePost = await mockToken.balanceOf(owner.address);

    await expect(contractBalancePost.toString()).to.equal(contractBalancePre.sub(tokenPrice).toString());
    await expect(ownerBalancePost.toString()).to.equal(ownerBalancePre.add(tokenPrice).toString());

    contractBalancePre = await mockToken.balanceOf(UniversalRaffle.address);
    ownerBalancePre = await mockToken.balanceOf(owner.address);

    await UniversalRaffle.refundRaffleTickets(raffleId, [tokenId + 1, tokenId + 2, tokenId + 3]);

    contractBalancePost = await mockToken.balanceOf(UniversalRaffle.address);
    ownerBalancePost = await mockToken.balanceOf(owner.address);

    await expect(contractBalancePost.toString()).to.equal(contractBalancePre.sub(tokenPrice.mul(3)).toString());
    await expect(ownerBalancePost.toString()).to.equal(ownerBalancePre.add(tokenPrice.mul(3)).toString());

    await expect(UniversalRaffle.refundRaffleTickets(raffleId, [tokenId + 3, tokenId + 4])).to.be.reverted;
  });

  it('should set allow list', async () => {
    const [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    const { UniversalRaffle, RaffleTickets } = await loadFixture(raffleWithNFTs);
    const raffleId = 1;

    await UniversalRaffle.toggleAllowList(raffleId);
    let config = await UniversalRaffle.getRaffleState(raffleId);
    expect(config[3]).to.equal(true);
    await UniversalRaffle.toggleAllowList(raffleId);
    config = await UniversalRaffle.getRaffleState(raffleId);
    expect(config[3]).to.equal(false);
    await UniversalRaffle.toggleAllowList(raffleId);

    const allowList = [];
    allowList.push([owner.address, 3]);
    allowList.push([addr1.address, 2]);
    allowList.push([addr2.address, 1]);
    allowList.push([addr3.address, 2]);
    allowList.push([addr4.address, 1]);

    await UniversalRaffle.setAllowList(raffleId, allowList);
    const allowance = await UniversalRaffle.getAllowList(raffleId, owner.address);
    expect(allowance).to.equal(3);

    const startTime = currentTime + 100;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    const buyAmount = 3;
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await expect(UniversalRaffle.buyRaffleTickets(raffleId, 1, { value: tokenPrice })).to.be.reverted;
    await expect(UniversalRaffle.connect(addr1).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) })).to.be.reverted;
  })

  it('should finalize raffle and claim prizes', async () => {
    const [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    const { UniversalRaffle, mockNFT, RaffleTickets } = await loadFixture(raffleWithNFTs);

    const startTime = currentTime + 100;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    const raffleId = 1;
    const buyAmount = 20;
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr1).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr2).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr3).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr4).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });

    const endTime = currentTime + 500;
    await ethers.provider.send('evm_setNextBlockTimestamp', [endTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.finalizeRaffle(raffleId);
    await expect(UniversalRaffle.finalizeRaffle(raffleId)).to.be.reverted;

    const check = await UniversalRaffle.getSlotInfo(raffleId, 1);
    const winner = await UniversalRaffle.getSlotWinner(raffleId, 1);
    expect(check[2]).to.equal(winner);

    let i = 1;
    for (let i = 1; i <= 10; i++) {
      const slot = await UniversalRaffle.getSlotInfo(raffleId, i);
      const depositedNFTs = await UniversalRaffle.getDepositedNftsInSlot(raffleId, i);
      expect(await mockNFT.ownerOf(depositedNFTs[0][1])).to.equal(UniversalRaffle.address);
      await UniversalRaffle.connect(await findSigner(slot[2])).claimERC721Rewards(raffleId, i, 1);
      if (depositedNFTs.length == 2) {
        await UniversalRaffle.connect(await findSigner(slot[2])).claimERC721Rewards(raffleId, i, 1);
      }
      expect(await mockNFT.ownerOf(depositedNFTs[0][1])).to.equal(slot[2]);
    }

    let config = await UniversalRaffle.getRaffleState(raffleId);
    expect(config[1]).to.equal(11);
    expect(config[2]).to.equal(11);
    expect(config[5]).to.equal(true);
    expect(config[4]).to.equal(false);
  });
});
