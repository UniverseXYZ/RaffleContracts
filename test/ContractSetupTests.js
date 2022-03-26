const { expect } = require("chai");
const { ethers, waffle, upgrades } = require('hardhat');
const { loadFixture } = waffle;

const vrfCoordinator = '0x6168499c0cFfCaCD319c818142124B7A15E857ab';
const link = '0x01BE23585060835E02B77ef475b0Cc51aA1e0709';
const keyHash = '0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc';
const subscriptionId = 677;

describe("Raffle Setup Security", async function () {
  const currentTime = Math.round((new Date()).getTime() / 1000);

  let purchaseToken;
  const zeroAddress = '0x0000000000000000000000000000000000000000';
  const startTime = currentTime + 100;
  const endTime = currentTime + 500;
  const maxTicketCount = 1000;
  const minTicketCount = 100;
  const tokenPrice = ethers.utils.parseEther("3.0");
  const totalSlots = 10;
  const raffleName = 'illestrater\'s Raffle';
  const raffleImage = 'https://i.ibb.co/SdN2kw3/ill.png';
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

    await expect(RaffleTickets.connect(addr1).initRaffleTickets(UniversalRaffle.address)).to.be.reverted;
    await expect(VRFInstance.connect(addr1).initVRF(UniversalRaffle.address)).to.be.reverted;
    await RaffleTickets.initRaffleTickets(UniversalRaffle.address);
    await VRFInstance.initVRF(UniversalRaffle.address);

    return { UniversalRaffle, RaffleTickets, VRFInstance, mockNFT, mockToken };
  };

  async function launchRaffles() {
    const [owner] = await ethers.getSigners();

    const { UniversalRaffle, RaffleTickets, VRFInstance, mockNFT, mockToken } = await loadFixture(deployContracts);

    await UniversalRaffle.createRaffle([
      owner.address,
      purchaseToken,
      startTime,
      endTime,
      maxTicketCount,
      minTicketCount,
      tokenPrice,
      totalSlots,
      raffleName,
      raffleImage,
      paymentSplits,
    ]);

    await UniversalRaffle.createRaffle([
      owner.address,
      zeroAddress,
      startTime,
      endTime,
      maxTicketCount,
      minTicketCount,
      tokenPrice,
      totalSlots,
      raffleName,
      raffleImage,
      paymentSplits,
    ]);

    return { UniversalRaffle, RaffleTickets, VRFInstance, mockNFT, mockToken };
  }

  async function raffleWithNFTs() {
    const [owner] = await ethers.getSigners();

    const { UniversalRaffle, RaffleTickets, VRFInstance, mockNFT, mockToken } = await loadFixture(launchRaffles);

    await mockNFT.mint(owner.address, 'nftURI');
    await mockNFT.setApprovalForAll(UniversalRaffle.address, true);
    await UniversalRaffle.depositNFTsToRaffle(1, [1], [[[1, mockNFT.address]]]);

    await mockNFT.mint(owner.address, 'nftURI');
    await mockNFT.mint(owner.address, 'nftURI');
    await UniversalRaffle.depositNFTsToRaffle(2, [1, 2], [[[2, mockNFT.address]], [[3, mockNFT.address]]]);

    return { UniversalRaffle, RaffleTickets, VRFInstance, mockNFT, mockToken };
  }

  it('should not allow directly minting Raffle Ticket NFTs', async () => {
    const [owner] = await ethers.getSigners();
    const { RaffleTickets } = await loadFixture(launchRaffles);

    await expect(RaffleTickets.mint(owner.address, 1, 1)).to.be.reverted;
  });

  it('should not allow directly calling VRF function', async () => {
    const [owner] = await ethers.getSigners();
    const { VRFInstance } = await loadFixture(launchRaffles);

    await expect(VRFInstance.getWinners(1)).to.be.reverted;
  });

  it('should check raffle config after DAO updates', async () => {
    const [owner, addr1] = await ethers.getSigners();
    const { UniversalRaffle, RaffleTickets, VRFInstance } = await loadFixture(raffleWithNFTs);

    let config = await UniversalRaffle.getContractConfig();
    expect(config[0]).to.equal(owner.address);
    expect(config[1]).to.equal(RaffleTickets.address);
    expect(config[2]).to.equal(VRFInstance.address);
    expect(config[3]).to.equal(2);
    expect(config[4]).to.equal(MAX_NUMBER_SLOTS);
    expect(config[5]).to.equal(MAX_BULK_PURCHASE);
    expect(config[6]).to.equal(NFT_SLOT_LIMIT);
    expect(config[7]).to.equal(ROYALTY_FEE_BPS);
    expect(config[8]).to.equal(false);
    expect(config[9]).to.equal(true);

    await UniversalRaffle.transferDAOownership(addr1.address);
    await expect(UniversalRaffle.setRaffleConfigValue(0, 50)).to.be.reverted;
    await UniversalRaffle.connect(addr1).setRaffleConfigValue(0, 50);
    await UniversalRaffle.connect(addr1).setRaffleConfigValue(1, 100);
    await UniversalRaffle.connect(addr1).setRaffleConfigValue(2, 50);
    await UniversalRaffle.connect(addr1).setRaffleConfigValue(3, 1000);

    config = await UniversalRaffle.getContractConfig();
    expect(config[4]).to.equal(50);
    expect(config[5]).to.equal(100);
    expect(config[6]).to.equal(50);
    expect(config[7]).to.equal(1000);
    expect(config[8]).to.equal(true);
  })
});
