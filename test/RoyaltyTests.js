const { expect } = require("chai");
const { ethers, waffle, upgrades } = require('hardhat');
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

describe("Raffle Royalty Tests", async function () {
  let randomWallet1 = ethers.Wallet.createRandom();
  let randomWallet2 = ethers.Wallet.createRandom();
  let randomWallet3 = ethers.Wallet.createRandom();
  let randomWallet4 = ethers.Wallet.createRandom();

  let purchaseToken;
  const zeroAddress = '0x0000000000000000000000000000000000000000';
  const maxTicketCount = 1000;
  const minTicketCount = 100;
  const tokenPrice = ethers.utils.parseEther("3.0");
  const totalSlots = 10;
  const emptySplits = []
  const paymentSplits = [[randomWallet3.address, 1000], [randomWallet4.address, 500]];

  const TEST_VRF = true;
  const MAX_NUMBER_SLOTS = 2000;
  const MAX_BULK_PURCHASE = 50;
  const NFT_SLOT_LIMIT = 100;
  const ROYALTY_FEE_BPS = 0;

  async function deployContracts() {
    const [owner, addr1] = await ethers.getSigners();

    const MockNFT = await ethers.getContractFactory('MockNFT');
    const MockToken = await ethers.getContractFactory('MockToken');
    const UniverseERC721 = await ethers.getContractFactory('UniverseERC721');
    const mockNFT = await MockNFT.deploy();
    const mockToken = await MockToken.deploy(ethers.utils.parseEther("10000"));
    const universeERC721 = await UniverseERC721.deploy("Non Fungible Universe", "NFU");
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
      owner.address
    );

    await UniversalRaffle.deployed();

    await RaffleTickets.initRaffleTickets(UniversalRaffle.address);
    await VRFInstance.initVRF(UniversalRaffle.address);
    await UniversalRaffle.setRoyaltiesRegistry(mockRoyaltiesRegistry.address);

    return { UniversalRaffle, RaffleTickets, mockNFT, universeERC721, mockToken };
  };

  async function launchRaffles() {
    const [owner, addr1] = await ethers.getSigners();

    const { UniversalRaffle, RaffleTickets, universeERC721, mockNFT, mockToken } = await loadFixture(deployContracts);

    const currentTime = Math.round((new Date()).getTime() / 1000);
    const startTime = currentTime + 50000;
    const endTime = currentTime + 100000;

    await UniversalRaffle.connect(addr1).createRaffle([
      addr1.address,
      zeroAddress,
      startTime,
      endTime,
      maxTicketCount,
      minTicketCount,
      tokenPrice,
      totalSlots,
      'Raffle Raffle Raffle',
      emptySplits,
    ]);

    await UniversalRaffle.connect(addr1).createRaffle([
      addr1.address,
      purchaseToken,
      startTime,
      endTime,
      maxTicketCount,
      minTicketCount,
      tokenPrice,
      totalSlots,
      'Raffle Raffle Raffle',
      emptySplits,
    ]);

    await UniversalRaffle.connect(addr1).createRaffle([
      addr1.address,
      purchaseToken,
      startTime,
      endTime,
      maxTicketCount,
      minTicketCount,
      tokenPrice,
      totalSlots,
      'Raffle Raffle Raffle',
      paymentSplits,
    ]);

    return { UniversalRaffle, RaffleTickets, universeERC721, mockNFT, mockToken };
  }

  async function raffleWithNFTs() {
    const [owner, addr1] = await ethers.getSigners();

    const { UniversalRaffle, RaffleTickets, universeERC721, mockNFT, mockToken } = await loadFixture(launchRaffles);

    let counter = 0;
    while (counter < 50) {
      await universeERC721.mint(addr1.address, 'nftURI', [[randomWallet1.address, 1000], [randomWallet2.address, 500]]);
      counter++;
    }

    const slotIndexes = [];
    let NFTs = [];
    for (let i = 1; i <= 10; i++) {
      slotIndexes.push(i);
      NFTs.push([[i, universeERC721.address]]);
    }

    await universeERC721.connect(addr1).setApprovalForAll(UniversalRaffle.address, true);
    await UniversalRaffle.connect(addr1).depositNFTsToRaffle(1, slotIndexes, NFTs);

    NFTs = [];
    for (let i = 11; i <= 20; i++) {
      NFTs.push([[i, universeERC721.address]]);
    }
    await UniversalRaffle.connect(addr1).depositNFTsToRaffle(2, slotIndexes, NFTs);

    NFTs = [];
    for (let i = 21; i <= 30; i++) {
      NFTs.push([[i, universeERC721.address]]);
    }
    await UniversalRaffle.connect(addr1).depositNFTsToRaffle(3, slotIndexes, NFTs);

    return { UniversalRaffle, RaffleTickets, mockNFT, universeERC721, mockToken };
  }


  it('should payout revenue without DAO fee in ETH', async () => {
    const [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    const { UniversalRaffle, mockToken, mockNFT, RaffleTickets } = await loadFixture(raffleWithNFTs);

    const currentTime = Math.round((new Date()).getTime() / 1000);
    const startTime = currentTime + 50000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    const raffleId = 1;
    const buyAmount = 20;
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr1).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr2).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr3).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr4).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });

    const endTime = currentTime + 100000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [endTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.finalizeRaffle(raffleId);
    await expect(UniversalRaffle.finalizeRaffle(raffleId)).to.be.reverted;

    const rafflerBalance = await ethers.provider.getBalance(addr1.address);
    await UniversalRaffle.connect(addr2).distributeCapturedRaffleRevenue(raffleId);
    await expect(UniversalRaffle.connect(addr2).distributeCapturedRaffleRevenue(raffleId)).to.be.reverted;
    const revenue = tokenPrice.mul(buyAmount * 5);
    const nftRoyalties = revenue.mul(1500).div(10000);
    expect(await ethers.provider.getBalance(UniversalRaffle.address)).to.equal(nftRoyalties);
    expect(await ethers.provider.getBalance(addr1.address)).to.equal(rafflerBalance.add(revenue.sub(nftRoyalties)));
  });

  it('should payout revenue without DAO fee in ERC20', async () => {
    const [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    const { UniversalRaffle, mockToken, mockNFT, RaffleTickets } = await loadFixture(raffleWithNFTs);

    const currentTime = Math.round((new Date()).getTime() / 1000);
    const startTime = currentTime + 50000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    const raffleId = 2;
    const buyAmount = 20;
    await mockToken.approve(UniversalRaffle.address, tokenPrice.mul(buyAmount * 5));
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });

    const endTime = currentTime + 100000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [endTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.finalizeRaffle(raffleId);
    await expect(UniversalRaffle.finalizeRaffle(raffleId)).to.be.reverted;

    const rafflerBalance = await mockToken.balanceOf(addr1.address);
    await UniversalRaffle.connect(addr2).distributeCapturedRaffleRevenue(raffleId);
    const revenue = tokenPrice.mul(buyAmount * 5);
    const nftRoyalties = revenue.mul(1500).div(10000);
    expect(await mockToken.balanceOf(UniversalRaffle.address)).to.equal(nftRoyalties);
    expect(await mockToken.balanceOf(addr1.address)).to.equal(rafflerBalance.add(revenue.sub(nftRoyalties)));
  });

  it('should payout revenue and royalties and DAO in ETH', async () => {
    const [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    const { UniversalRaffle, mockNFT, RaffleTickets } = await loadFixture(raffleWithNFTs);

    const currentTime = Math.round((new Date()).getTime() / 1000);
    const startTime = currentTime + 50000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.setRaffleConfigValue(3, 1000);

    const raffleId = 1;
    const buyAmount = 20;
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr1).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr2).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr3).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.connect(addr4).buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });

    const endTime = currentTime + 100000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [endTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.finalizeRaffle(raffleId);
    await expect(UniversalRaffle.finalizeRaffle(raffleId)).to.be.reverted;

    const rafflerBalance = await ethers.provider.getBalance(addr1.address);
    await UniversalRaffle.connect(addr2).distributeCapturedRaffleRevenue(raffleId);
    const revenue = tokenPrice.mul(buyAmount * 5);
    const nftRoyalties = revenue.mul(1500).div(10000);
    const daoRevenue = revenue.sub(nftRoyalties).mul(1000).div(10000);
    const daoBalance = await ethers.provider.getBalance(owner.address);
    expect(await ethers.provider.getBalance(UniversalRaffle.address)).to.equal(nftRoyalties.add(daoRevenue));
    expect(await ethers.provider.getBalance(addr1.address)).to.equal(rafflerBalance.add(revenue.sub(nftRoyalties).sub(daoRevenue)));
    await UniversalRaffle.connect(addr2).distributeRoyalties(zeroAddress);
    expect(await ethers.provider.getBalance(owner.address)).to.equal(daoBalance.add(daoRevenue));

    for (let i = 1; i <= 10; i++) {
      await UniversalRaffle.distributeSecondarySaleFees(raffleId, i, 1);
    }

    expect(await ethers.provider.getBalance(randomWallet1.address)).to.equal(nftRoyalties.mul(1000).div(1500));
    expect(await ethers.provider.getBalance(randomWallet2.address)).to.equal(nftRoyalties.mul(500).div(1500));
  });

  it('should payout revenue and royalties and DAO in ERC20', async () => {
    const [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    const { UniversalRaffle, mockToken, mockNFT, RaffleTickets } = await loadFixture(raffleWithNFTs);

    const currentTime = Math.round((new Date()).getTime() / 1000);
    const startTime = currentTime + 50000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.setRaffleConfigValue(3, 1000);

    const raffleId = 2;
    const buyAmount = 20;
    await mockToken.approve(UniversalRaffle.address, tokenPrice.mul(buyAmount * 5));
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });

    const endTime = currentTime + 100000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [endTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.finalizeRaffle(raffleId);
    await expect(UniversalRaffle.finalizeRaffle(raffleId)).to.be.reverted;

    const rafflerBalance = await mockToken.balanceOf(addr1.address);
    await UniversalRaffle.connect(addr2).distributeCapturedRaffleRevenue(raffleId);
    const revenue = tokenPrice.mul(buyAmount * 5);
    const nftRoyalties = revenue.mul(1500).div(10000);
    const daoRevenue = revenue.sub(nftRoyalties).mul(1000).div(10000);
    const daoBalance = await mockToken.balanceOf(owner.address);
    expect(await mockToken.balanceOf(UniversalRaffle.address)).to.equal(nftRoyalties.add(daoRevenue));
    expect(await mockToken.balanceOf(addr1.address)).to.equal(rafflerBalance.add(revenue.sub(nftRoyalties).sub(daoRevenue)));
    await UniversalRaffle.connect(addr2).distributeRoyalties(mockToken.address);
    expect(await mockToken.balanceOf(owner.address)).to.equal(daoBalance.add(daoRevenue));

    for (let i = 1; i <= 10; i++) {
      await UniversalRaffle.distributeSecondarySaleFees(raffleId, i, 1);
    }

    expect(await mockToken.balanceOf(randomWallet1.address)).to.equal(nftRoyalties.mul(1000).div(1500));
    expect(await mockToken.balanceOf(randomWallet2.address)).to.equal(nftRoyalties.mul(500).div(1500));
  });


  it('should payout raffle splits and royalties and DAO in ERC20', async () => {
    const [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    const { UniversalRaffle, mockToken, mockNFT, RaffleTickets } = await loadFixture(raffleWithNFTs);

    const currentTime = Math.round((new Date()).getTime() / 1000);
    const startTime = currentTime + 50000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.setRaffleConfigValue(3, 1000);

    const raffleId = 3;
    const buyAmount = 20;
    await mockToken.approve(UniversalRaffle.address, tokenPrice.mul(buyAmount * 5));
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });
    await UniversalRaffle.buyRaffleTickets(raffleId, buyAmount, { value: tokenPrice.mul(buyAmount) });

    const endTime = currentTime + 100000;
    await ethers.provider.send('evm_setNextBlockTimestamp', [endTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.finalizeRaffle(raffleId);
    await expect(UniversalRaffle.finalizeRaffle(raffleId)).to.be.reverted;

    const rafflerBalance = await mockToken.balanceOf(addr1.address);
    await UniversalRaffle.connect(addr2).distributeCapturedRaffleRevenue(raffleId);
    const revenue = tokenPrice.mul(buyAmount * 5);
    const nftRoyalties = revenue.mul(1500).div(10000);
    const daoRevenue = revenue.sub(nftRoyalties).mul(1000).div(10000);
    const daoBalance = await mockToken.balanceOf(owner.address);
    const rafflerSplits = revenue.sub(nftRoyalties).sub(daoRevenue).mul(1500).div(10000);
    expect(await mockToken.balanceOf(UniversalRaffle.address)).to.equal(nftRoyalties.add(daoRevenue));
    expect(await mockToken.balanceOf(addr1.address)).to.equal(rafflerBalance.add(revenue.sub(nftRoyalties).sub(daoRevenue).sub(rafflerSplits)));
    await UniversalRaffle.connect(addr2).distributeRoyalties(mockToken.address);
    expect(await mockToken.balanceOf(owner.address)).to.equal(daoBalance.add(daoRevenue));

    for (let i = 1; i <= 10; i++) {
      await UniversalRaffle.distributeSecondarySaleFees(raffleId, i, 1);
    }

    expect(await mockToken.balanceOf(randomWallet1.address)).to.equal(nftRoyalties.mul(1000).div(1500));
    expect(await mockToken.balanceOf(randomWallet2.address)).to.equal(nftRoyalties.mul(500).div(1500));
    expect(await mockToken.balanceOf(randomWallet3.address)).to.equal(rafflerSplits.mul(1000).div(1500));
    expect(await mockToken.balanceOf(randomWallet4.address)).to.equal(rafflerSplits.mul(500).div(1500));
  });
});
