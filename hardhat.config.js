require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require('hardhat-contract-sizer');
require("@nomiclabs/hardhat-etherscan");
require("@openzeppelin/hardhat-upgrades");
require('dotenv').config();


// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.11",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    ropsten: {
      url: `https://ropsten.infura.io/v3/${ process.env.INFURA_KEY }`,
      accounts: [`0x${ process.env.MM_PRIVATE_KEY }`],
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${ process.env.INFURA_KEY }`,
      accounts: [`0x${ process.env.MM_PRIVATE_KEY }`],
    },
  },
  etherscan: {
    apiKey: `${ process.env.ETHERSCAN }`
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  gasReporter: {
    enabled: true
  },
  mocha: {
    timeout: 200000
  }
};
