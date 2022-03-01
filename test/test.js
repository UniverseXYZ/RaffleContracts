const { expect } = require("chai");
const { ethers } = require("hardhat");
const { waffle, upgrades } = require('hardhat');
const { loadFixture } = waffle;

const vrfCoordinator = '0x6168499c0cFfCaCD319c818142124B7A15E857ab';
const link = '0x01BE23585060835E02B77ef475b0Cc51aA1e0709';
const keyHash = '0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc';
const subscriptionId = 677;

describe("UniversalRaffle", async function () {
  const currentTime = Math.round((new Date()).getTime() / 1000);

  async function deployContracts() {
    const [owner, addr1] = await ethers.getSigners();

    const MockNFT = await ethers.getContractFactory('MockNFT');
    const MockToken = await ethers.getContractFactory('MockToken');
    const mockNFT = await MockNFT.deploy();
    const mockToken = await MockToken.deploy(ethers.utils.parseEther("10000"));

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
      2000,
      100,
      0,
      owner.address,
      RaffleTickets.address,
      VRFInstance.address,
      [mockToken.address],
      mockRoyaltiesRegistry.address
    );


    await UniversalRaffle.deployed();

    RaffleTickets.initRaffleTickets(UniversalRaffle.address);
    VRFInstance.initVRF(UniversalRaffle.address);

    return { UniversalRaffle, RaffleTickets, mockNFT, mockToken };
  };

  async function launchRaffle() {
    const [owner] = await ethers.getSigners();

    const { UniversalRaffle, RaffleTickets, mockNFT, mockToken } = await loadFixture(deployContracts);

    const purchaseToken = mockToken.address;
    const startTime = currentTime + 100;
    const endTime = currentTime + 500;
    const maxTicketCount = 1000;
    const minTicketCount = 100;
    const tokenPrice = ethers.utils.parseEther("3.0");
    const totalSlots = 10;
    const paymentSplits = [];

    auction = await UniversalRaffle.createRaffle([
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

  it('should create raffle', async () => {
    const [owner] = await ethers.getSigners();
    const { UniversalRaffle, mockNFT, mockToken } = await loadFixture(launchRaffle);

    const purchaseToken = mockToken.address;
    const startTime = currentTime + 100;
    const endTime = currentTime + 500;
    const maxTicketCount = 1000;
    const minTicketCount = 100;
    const tokenPrice = ethers.utils.parseEther("3.0");
    const totalSlots = 10;
    const paymentSplits = [];

    const raffleInfo = await UniversalRaffle.getRaffleInfo(1);
    console.log(raffleInfo);
    expect(raffleInfo[0][0]).to.equal(owner.address);
    expect(raffleInfo[0][1]).to.equal(purchaseToken);
    expect(raffleInfo[0][2].toNumber()).to.equal(startTime);
    expect(raffleInfo[0][3].toNumber()).to.equal(endTime);
    expect(raffleInfo[0][4].toNumber()).to.equal(maxTicketCount);
    expect(raffleInfo[0][5].toNumber()).to.equal(minTicketCount);
    expect(raffleInfo[0][6].toString()).to.equal(tokenPrice.toString());
    expect(raffleInfo[0][7]).to.equal(totalSlots);
    expect(JSON.stringify(raffleInfo[0][8])).to.equal(JSON.stringify(paymentSplits));
  })

  it('should purchase one raffle ticket', async () => {
    const [owner] = await ethers.getSigners();
    const { UniversalRaffle, RaffleTickets, mockNFT, mockToken } = await loadFixture(launchRaffle);

    const startTime = currentTime + 100;
    const tokenPrice = ethers.utils.parseEther("3.0");
    const buyAmount = 20;

    await mockNFT.mint(owner.address, 'nftURI');
    await mockNFT.approve(UniversalRaffle.address, 1);

    await mockToken.approve(UniversalRaffle.address, tokenPrice.mul(buyAmount));

    await UniversalRaffle.depositERC721(1, 1, [[1, mockNFT.address]]);

    await ethers.provider.send('evm_setNextBlockTimestamp', [startTime]);
    await ethers.provider.send('evm_mine');

    await UniversalRaffle.buyRaffleTicket(1, buyAmount);

    const raffleId = 1;
    const tokenId = raffleId * 10000000 + 1;
    expect(await RaffleTickets.ownerOf(tokenId)).to.equal(owner.address);
    expect(await RaffleTickets.balanceOf(owner.address)).to.equal(20);
  })
});
