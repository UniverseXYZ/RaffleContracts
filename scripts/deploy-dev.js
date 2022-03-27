// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const ethers = hre.ethers;

const vrfCoordinator = '0x6168499c0cFfCaCD319c818142124B7A15E857ab';
const link = '0x01BE23585060835E02B77ef475b0Cc51aA1e0709';
const keyHash = '0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc';
const subscriptionId = 677;

async function main() {
  const currentTime = Math.round((new Date()).getTime() / 1000);

  const zeroAddress = '0x0000000000000000000000000000000000000000';
  const startTime = currentTime + 600; // 10 mins
  const endTime = currentTime + 900; // 15 mins
  const maxTicketCount = 1000;
  const minTicketCount = 10;
  const tokenPrice = ethers.utils.parseEther("0.0007");
  const totalSlots = 10;
  const raffleName = 'illestrater\'s Raffle';
  const ticketColorOne = 'ffdf29';
  const ticketColorTwo = 'ff0019';
  const paymentSplits = [];
  const UNSAFE_VRF_TESTING = false;

  const [owner] = await ethers.getSigners();

  const RaffleTicketsFactory = await hre.ethers.getContractFactory("RaffleTickets");
  const RaffleTickets = await RaffleTicketsFactory.deploy();
  await RaffleTickets.deployed();
  console.log('Raffle Tickets deployed', RaffleTickets.address);

  const VRF = await hre.ethers.getContractFactory("RandomNumberGenerator");
  const VRFInstance = await VRF.deploy(
    vrfCoordinator, link, keyHash, subscriptionId, RaffleTickets.address
  );
  await VRFInstance.deployed();
  console.log('VRF deployed', VRFInstance.address);

  const MockRoyaltiesRegistry =  await ethers.getContractFactory('MockRoyaltiesRegistry');
  const mockRoyaltiesRegistry = await upgrades.deployProxy(MockRoyaltiesRegistry, [], {initializer: "__RoyaltiesRegistry_init"});
  console.log('Mock Royalties deployed', mockRoyaltiesRegistry.address);

  const UniversalRaffleCore = await hre.ethers.getContractFactory("UniversalRaffleCore");
  const CoreInstance = await UniversalRaffleCore.deploy();
  await CoreInstance.deployed();
  console.log('Raffle Core deployed', CoreInstance.address);

  const UniversalRaffleCoreTwo = await hre.ethers.getContractFactory("UniversalRaffleCoreTwo");
  const CoreLibInstance = await UniversalRaffleCoreTwo.deploy();
  await CoreLibInstance.deployed();
  console.log('Raffle Core Two deployed', CoreInstance.address);

  const UniversalRaffleFactory = await ethers.getContractFactory("UniversalRaffle",
  {
    libraries: {
      UniversalRaffleCore: CoreInstance.address,
      UniversalRaffleCoreTwo: CoreLibInstance.address
    }
  });

  const UniversalRaffle = await UniversalRaffleFactory.deploy(
    UNSAFE_VRF_TESTING,
    2000,
    50,
    100,
    0,
    owner.address,
    RaffleTickets.address,
    VRFInstance.address,
    [],
    mockRoyaltiesRegistry.address
  );

  await UniversalRaffle.deployed();
  console.log('Raffle deployed', UniversalRaffle.address);

  await RaffleTickets.initRaffleTickets(UniversalRaffle.address);
  await VRFInstance.initVRF(UniversalRaffle.address);

  await UniversalRaffle.createRaffle([
    owner.address,
    zeroAddress,
    startTime,
    endTime,
    maxTicketCount,
    minTicketCount,
    totalSlots,
    tokenPrice,
    raffleName,
    ticketColorOne,
    ticketColorTwo,
    paymentSplits,
  ]);


  await new Promise(resolve => setTimeout(resolve, 20000));


  try {
    await hre.run("verify:verify", {
      address: RaffleTickets.address,
    });
  } catch (e) {
    console.log('got error', e);
  }

  console.log('Raffle Tickets verified');

  try {
    await hre.run("verify:verify", {
      address: VRFInstance.address,
      constructorArguments: [
        vrfCoordinator, link, keyHash, subscriptionId, RaffleTickets.address
      ],
    });
  } catch (e) {
    console.log('got error', e);
  }
  console.log('VRF verified');

  try {
    await hre.run("verify:verify", {
      address: mockRoyaltiesRegistry.address
    });
  } catch (e) {
    console.log('got error', e);
  }

  console.log('Mock Royalties verified');

  try {
    await hre.run("verify:verify", {
      address: CoreInstance.address
    });
  } catch (e) {
    console.log('got error', e);
  }

  console.log('Raffle Core verified');

  try {
    await hre.run("verify:verify", {
      address: CoreLibInstance.address
    });
  } catch (e) {
    console.log('got error', e);
  }

  console.log('Raffle Core Two verified');

  try {
    await hre.run("verify:verify", {
      address: UniversalRaffle.address,
      constructorArguments: [
        UNSAFE_VRF_TESTING,
        2000,
        50,
        100,
        0,
        owner.address,
        RaffleTickets.address,
        VRFInstance.address,
        [],
        mockRoyaltiesRegistry.address
      ],
    });
  } catch (e) {
    console.log('got error', e);
  }

  console.log('Raffle verified');
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
