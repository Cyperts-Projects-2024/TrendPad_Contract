async function main() {
  const Token = await ethers.getContractFactory("TrendLock");
  const token = await Token.deploy();
  console.log("Token address:", token.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });