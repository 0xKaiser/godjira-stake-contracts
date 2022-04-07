const { ethers } = require("hardhat")

async function main() {
  const tokenUri = "https://gladiators-metadata-api.herokuapp.com/api/token"

  const Genesis = await ethers.getContractFactory("Genesis");
  const genesis = await Genesis.deploy("genesis", "genesis", tokenUri);
  console.log("Genesis deployed to:", genesis.address);

  const Gen2 = await ethers.getContractFactory("Gen2");
  const gen2 = await Gen2.deploy("gen2", "gen2", tokenUri);
  console.log("Gen2 deployed to:", gen2.address);

  const JiraToken = await ethers.getContractFactory('JiraToken')
  const jiraToken = await JiraToken.deploy()
  console.log("JiraToken deployed to:", jiraToken.address);

  const Staking = await ethers.getContractFactory('Staking')
  const stakingV1 = await Staking.deploy()
  console.log("Staking deployed to:", stakingV1.address);

  const Proxy = await ethers.getContractFactory("UnstructuredProxy")
  const proxy = await Proxy.deploy()
  console.log("Proxy deployed to:", proxy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
