import '@typechain/hardhat'
import "@nomiclabs/hardhat-waffle";
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
    currency: 'USD',
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
} as HardhatUserConfig;
