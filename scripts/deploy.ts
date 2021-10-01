import { ethers } from "hardhat";

const REVERSE_REGISTRY_ADDRESS = {
	default: '0x0000000000000000000000000000000000000000',
  ropsten: "0x72c33B247e62d0f1927E8d325d0358b8f9971C68",
  rinkeby: "0x196eC7109e127A353B709a20da25052617295F6f",
  goerli: "0x333Fc8f550043f239a2CF79aEd5e9cF4A20Eb41e",
  mainnet: "0x3671aE578E63FdF66ad4F3E12CC0c0d71Ac7510C",
} as Record<string, string>;

async function main() {
  const [owner] = await ethers.getSigners();
  const IOweYou = await ethers.getContractFactory("IOweYou");
  const iOweYou = await IOweYou.deploy(
    REVERSE_REGISTRY_ADDRESS[process.env.HARDHAT_NETWORK || 'default']
  );

  await iOweYou.deployed();

  console.log(
    `ReverseRecords deployed to ${process.env.HARDHAT_NETWORK}:${iOweYou.address}`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
