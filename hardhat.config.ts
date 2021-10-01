import "dotenv/config";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-gas-reporter";
import { task, HardhatUserConfig } from "hardhat/config";

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

export default {
  gasReporter: {
    currency: "USD",
    gasPrice: 60,
  },
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    hardhat: {
      forking: {
        url: `https://eth-ropsten.alchemyapi.io/v2/${process.env.ALCHEMY_ROPSTEN}`,
        blockNumber: 11133070,
      },
    },
    ropsten: {
      url: `https://eth-ropsten.alchemyapi.io/v2/${process.env.ALCHEMY_ROPSTEN}`,
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${process.env.ALCHEMY_RINKEBY}`,
      accounts: [process.env.RINKEBY_KEY],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
} as HardhatUserConfig;
