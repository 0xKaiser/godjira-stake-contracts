require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("@nomiclabs/hardhat-etherscan");
require('@openzeppelin/hardhat-upgrades');
require("solidity-coverage");
require('hardhat-deploy');
require('dotenv').config()

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

const MNEMONIC = process.env.MNEMONIC || 'sample-mnemonic'
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || 'etherscan-api-key'

module.exports = {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      }
    }
  },
  namedAccounts: {
    deployer: 0,
  },
  networks: {
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/4e4a4359db564bcf865aae6ece530d13`,
      accounts: {
        mnemonic: MNEMONIC
      }
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/4e4a4359db564bcf865aae6ece530d13`,
      accounts: {
        mnemonic: MNEMONIC
      }
    }
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY
  }
};
