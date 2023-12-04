const hre = require("hardhat");

async function main() {
  const Token = await hre.ethers.getContractFactory("DjangoUnchanied");
  const token = await Token.deploy();

  await token.deployed();

  console.log("Token was deployed, CA: ", token.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
