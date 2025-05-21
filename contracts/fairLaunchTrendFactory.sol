        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.0;

        import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
        import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
        import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
        import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
        import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
        import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
        import "./SafeMath.sol";

        interface ITrendFairLaunchPool {
        struct SaleInfo {
                address saleToken;
                uint256 tokenAmount;
                uint256 liquidityToken;
                uint256 softCap;
                uint256 maxPay;
                uint256 lpPercent;
                bool affilation;
                bool isEnableWhitelist;
                bool isBuyBackEnabled;
                bool isVestingEnabled;
                string metadataURL;
            }

                struct Timestamps {
                    uint256 startTimestamp;  
                    uint256 endTimestamp;    
                    uint256 claimTimestamp;  
                    uint256 unlockTimestamp; 
                }

                struct DEXInfo {
                    address router;
                    address factory;
                    address weth;
                }

            struct VestingInfo {
            uint8 TGEPercent;
            uint256 cycleTime;
            uint8 releasePercent;
            uint256 startTime;
            }

         struct BuyBackInfo{
           uint8 buybackPercentage;
           address buyBackMangerAddrress;
            }

            function initialize(
                SaleInfo memory _saleInfo,
                Timestamps memory _timestamps,
                DEXInfo memory _dexInfo,
                address _locker,
                address _feeWallet,
                uint256 _feeAmount,
                uint8 _affiliateRate
            ) external;

            function setVesting(VestingInfo memory _vestingInfo) external;

            function transferOwnership(address newOwner) external;
            
            function setBuyBack(BuyBackInfo memory _buyBackInfo) external ;

        }

        interface IBuyBackManager{
            function getBuyBackDefaultInfo() external view returns (
                uint256 _amountPerBuyBack,
                uint256 _minBuyBackDeley, 
                uint256 _maxBuyBackDeley);

            function setBuybackConfig(
                address _pool,
                address _tokenAddress,
                address _routerAddress,
                uint8 _percentage,
                uint256 _totalBuyBackAmount
            ) external;
        }

        contract TrendPadIDOFairLaunchFactoryV2 is Initializable ,OwnableUpgradeable ,UUPSUpgradeable{
            using SafeERC20 for ERC20;
            using SafeMath for uint256;
            address public feeWallet;
            uint256 public feePercent;
            address public  fairLaunchTrendPoolImplementation;
        
            address[] public TrendPools; //to Storing the all pool data 
            mapping(address => address[]) private userPools; //get the user pool
            address public buyBackManagerAddress;


            event IDOCreated(
                address indexed owner,
                address TrendPool,
                address indexed rewardToken 
                );

            event TokenFeeUpdated(address newFeeToken);
            event feePercentUpdated(uint256 newfeePercent);
            event FeeWalletUpdated(address newFeeWallet);

            function initialize(uint256 _feePercent, address _feeWallet) public initializer {
                __Ownable_init(msg.sender);
                __UUPSUpgradeable_init();
                feeWallet = _feeWallet;
                feePercent = _feePercent;
            }

            function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
            function getTrendPools() public view returns (address[] memory) {
            return TrendPools;
            }

            function setFeePercent(uint256 _newfeePercent) external onlyOwner {
                feePercent = _newfeePercent;
                emit feePercentUpdated(_newfeePercent);
            }
            
            function setFeeWallet(address _newFeeWallet) external onlyOwner {
                feeWallet = _newFeeWallet;
                emit FeeWalletUpdated(_newFeeWallet);
            }
            
            function setBuyBackManagerAddress(address _buyBackManagerAddress) external onlyOwner {
            require(_buyBackManagerAddress != address(0), "Invalid address");
            buyBackManagerAddress = _buyBackManagerAddress;
            }

            function setTrendPoolImplementation(address _implementation) external onlyOwner {
            require(_implementation != address(0), "Invalid implementation");
            fairLaunchTrendPoolImplementation = _implementation;
            }

            function processIDOCreate(
                uint256 transferAmount,
                ERC20 _saleToken,
                address TrendPoolAddress
                ) private {
                _saleToken.safeTransferFrom(
                    msg.sender,
                    TrendPoolAddress,
                    transferAmount
                );
                
                TrendPools.push(TrendPoolAddress);
                userPools[msg.sender].push(TrendPoolAddress);
                emit IDOCreated(
                    msg.sender,
                    TrendPoolAddress,
                    address(_saleToken)
                );
            }

        function createFairLaunch(
                ITrendFairLaunchPool.SaleInfo memory _saleInfo,
                ITrendFairLaunchPool.Timestamps memory _timestamps,
                ITrendFairLaunchPool.DEXInfo memory _dexInfo,
                ITrendFairLaunchPool.VestingInfo memory _vestingInfo,
                address _lokerFactoryAddress,
                uint8  _affiliateRate,
                uint8 _buyBackPercent
                )
        external {
            require(fairLaunchTrendPoolImplementation != address(0), "Implementation not set");
        
                bytes memory initData = abi.encodeWithSelector(
                ITrendFairLaunchPool.initialize.selector,
                _saleInfo,
                _timestamps,
                _dexInfo,   
                _lokerFactoryAddress,
                feeWallet,
                feePercent,
                _affiliateRate
            );
            // Deploy proxy
            ERC1967Proxy proxy = new ERC1967Proxy(fairLaunchTrendPoolImplementation, initData);
            address fairLaunchTrendPoolProxy = address(proxy);
            ITrendFairLaunchPool(fairLaunchTrendPoolProxy).transferOwnership(msg.sender);
            uint8 tokenDecimals = ERC20(_saleInfo.saleToken).decimals();
            uint256 saleTokenAmount = _saleInfo.tokenAmount;
            if(_saleInfo.lpPercent > 0){
                saleTokenAmount = saleTokenAmount.add(getFairLaunchTokenAmount(saleTokenAmount,_saleInfo.lpPercent,tokenDecimals));
            }
        //set buyBack 
            if (_saleInfo.isBuyBackEnabled &&_buyBackPercent > 0) {
                require(_saleInfo.lpPercent.add(_buyBackPercent)<= 100 &&_saleInfo.lpPercent.add(_buyBackPercent)>=51, "LP and buyback percent must be Less than and equal 100 and greater than 51");
                require(buyBackManagerAddress != address(0), "Buyback manager address not set");
                uint256 calulatedAmount = (_saleInfo.softCap * _buyBackPercent) / 100;
                IBuyBackManager(buyBackManagerAddress).setBuybackConfig(
                fairLaunchTrendPoolProxy,
                    _saleInfo.saleToken,
                    _dexInfo.router,
                    _buyBackPercent,
                    calulatedAmount
                );
                // update the buyback info in the poolcontract 
                ITrendFairLaunchPool(fairLaunchTrendPoolProxy).setBuyBack(
                    ITrendFairLaunchPool.BuyBackInfo({
                        buybackPercentage: _buyBackPercent,
                        buyBackMangerAddrress: buyBackManagerAddress
                    })
                );

    
            } 
    // if select the vesting so set the vesting info in the pool contract
            if(_saleInfo.isVestingEnabled) {
            ITrendFairLaunchPool(fairLaunchTrendPoolProxy).setVesting(_vestingInfo);
            }

            processIDOCreate(
                saleTokenAmount,
                ERC20(_saleInfo.saleToken),
                fairLaunchTrendPoolProxy
            );
        }

        function getFairLaunchTokenAmount(
            uint256 _amount, 
            uint lpPercent, 
            uint256 _decimals
        ) public view returns (uint256) {
            uint256 _ethAmount = 1 ether; // 1 ETH in wei
            uint256 fee = (_ethAmount * feePercent) / 100; // Calculate fee
            uint256 adjustedEthAmount = _ethAmount - fee; // Adjust ETH amount after fee
            uint256 lpAdjusted = (adjustedEthAmount * lpPercent) / 100; // Adjust by lpPercent
            uint256 finalAmount = (lpAdjusted * _amount) / (10 ** _decimals); // Final amount
            return finalAmount;
        }

        function getUserPools(address _user) public view returns (address[] memory) {
                return userPools[_user];
            }
        function getBuyBackManagerAddress() public view returns (address) {
                return buyBackManagerAddress;
            }

        function getFeeWallet() public view returns (address) {
                return feeWallet;
            }
        function getFeePercent() public view returns (uint256) {
                return feePercent;
            }
        function getFairLaunchTrendPoolImplementation() public view returns (address) {
                return fairLaunchTrendPoolImplementation;
            }
        function getTrendPoolsCount() public view returns (uint256) {
                return TrendPools.length;
            }
            
        function getUserPoolCount(address _user) public view returns (uint256) {
                return userPools[_user].length;
            }

        function isContract(address _addr) private view returns (bool) {
                uint32 size;
                assembly {
                    size := extcodesize(_addr)
                }
                return (size > 0);
            }

        }