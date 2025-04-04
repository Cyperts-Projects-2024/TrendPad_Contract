async function main() {
  const Token = await ethers.getContractFactory("AirdropFactory");
  const FeeWallet ="0xbAD2E8F76d7004c76BA1d1b16100754258caa9Ed"
  const feeAmount = ethers.utils.parseEther("0");

  const token = await Token.deploy(FeeWallet,feeAmount);
  console.log("Token address:", token.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });