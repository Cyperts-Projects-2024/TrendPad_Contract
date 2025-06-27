// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SafeMath.sol";

interface IPancakeRouter {
    
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IBurnableToken {
    function burn(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract BuyBackManagerV2 is Initializable, OwnableUpgradeable , ReentrancyGuardUpgradeable ,UUPSUpgradeable {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;    


    struct BuyBackConfig {
        address tokenAddress;
        address tokenBAddress; // Optional, if needed for dual token pools
        address routerAddress;
        uint8 percentage;
        uint256 totalBuyBackAmount;
        uint256 boughtBackAmount;
        uint256 AmountPerBuyBack;
        uint256 minBuyBackDeley;
        uint256 maxBuyBackDeley;
        uint256 nextbuyBackTime;
        uint256 lastbuyBackTime;
        bool isConfigured;
        bool isNative;
    }
    
    uint256 public amountPerBuyBack;
    uint256 public minBuyBackDeley;
    uint256 public maxBuyBackDeley;

    mapping(address => BuyBackConfig) public poolConfig;
    mapping(address => uint256) public buyBackAmount;
    mapping(address => bool) public isAllowed;
    uint private  MAX_PERCENTAGE ;
     uint private x;
          uint private y;

    address public authorizedAddress;

    // Events
    event BuybackAndBurn(address indexed pool, address indexed token, uint256 amount);
    event PoolConfigured(address indexed pool, address indexed tokenA, address tokenB,  uint8 percentage);
    event PoolFinalized(address indexed pool, uint256 amount);
    event PermissionUpdated(address indexed user, bool allowed);

   function initialize(uint256 _amountPerBuyBack, uint256 _minBuyBackDeley, uint256 _maxBuyBackDeley) public initializer {
         __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        amountPerBuyBack = _amountPerBuyBack;
        minBuyBackDeley = _minBuyBackDeley;
        maxBuyBackDeley = _maxBuyBackDeley;
    }
      function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
    modifier onlyAuthorized(address _pool,address _user) {
    require(_pool != address(0), "Invalid pool address");
    require(_user != address(0), "Invalid user address");
    require(checkUserAllow(_pool, _user), "Not allowed yet");
    require(poolConfig[_pool].isConfigured, "Pool not configured or not finalized");
    _;
}

    // Set global buyback parameters
    function setGlobalBuyBackParams(
        uint256 _amountPerBuyBack,
        uint256 _minBuyBackDeley,
        uint256 _maxBuyBackDeley
    ) external onlyOwner  {
        require(_minBuyBackDeley <= _maxBuyBackDeley, "Min delay must be <= max delay");
        amountPerBuyBack = _amountPerBuyBack;
        minBuyBackDeley = _minBuyBackDeley;
        maxBuyBackDeley = _maxBuyBackDeley;
    }

    function setBuybackConfig(
            address _pool,
            address _tokenAAddress,
            address _tokenBAddress,
            address _routerAddress,
            uint8 _percentage,
            uint256 _totalBuyBackAmount,
            bool isNativeStatus
        ) external  {
            require(_pool != address(0), "Invalid pool address");
            require(_tokenAAddress != address(0), "Invalid token address");
            require(_tokenBAddress != address(0), "Invalid token B address");
            require(_routerAddress != address(0), "Invalid router address");
            require(_percentage > 0 && _percentage <= 100, "Percentage must be between 1-100");
            require(_totalBuyBackAmount > 0, "Total buyback amount must be > 0");
            
            poolConfig[_pool] = BuyBackConfig({
                tokenAddress: _tokenAAddress,
                tokenBAddress: _tokenBAddress,
                routerAddress: _routerAddress,
                percentage: _percentage,
                totalBuyBackAmount:_totalBuyBackAmount,
                boughtBackAmount: 0,
                AmountPerBuyBack: amountPerBuyBack,
                minBuyBackDeley: minBuyBackDeley,
                maxBuyBackDeley: maxBuyBackDeley,
                nextbuyBackTime: 0, 
                lastbuyBackTime: 0,  
                isConfigured: false,
                isNative: isNativeStatus
            });
        
            emit PoolConfigured(_pool, _tokenAAddress,_tokenBAddress, _percentage);
        }

    function getBuyBackDefaultInfo() external view returns (
        uint256 _amountPerBuyBack,
        uint256 _minBuyBackDeley, 
        uint256 _maxBuyBackDeley
    ) {
        return (amountPerBuyBack, minBuyBackDeley, maxBuyBackDeley);
    }

    function getPoolBuyBackInfo(address _pool) external view returns (BuyBackConfig memory) {
        BuyBackConfig storage config = poolConfig[_pool];
        return config;
    }
    
    function getBuyBackRemainAmount(address _pool) external view returns (uint256) {
        return buyBackAmount[_pool];
    }

    function finalizeBuyBackConfig(address _pool,uint256 _amount) external payable {
        require(_pool != address(0), "Invalid pool address");
        require(!poolConfig[_pool].isConfigured, "Pool already configured");
        require(poolConfig[_pool].totalBuyBackAmount > 0, "Total buyback amount must be > 0");
         BuyBackConfig storage config = poolConfig[_pool];
        if (config.isNative) {
        require(msg.value == _amount, "ETH amount mismatch");
    } else {
        require(msg.value == 0, "Don't send ETH for token buybacks");
        IERC20(config.tokenBAddress).safeTransferFrom(msg.sender, address(this), _amount);
    }

        buyBackAmount[_pool] = _amount;
       
        config.isConfigured = true;
        config.totalBuyBackAmount=_amount;
        config.nextbuyBackTime = block.timestamp.add(config.minBuyBackDeley);
        config.lastbuyBackTime = block.timestamp;
        
        emit PoolFinalized(_pool, _amount);
    }
    
    function buybackAndBurn(address _pool) nonReentrant onlyAuthorized(_pool,msg.sender) external  {
        BuyBackConfig storage config = poolConfig[_pool];
        uint256 availableBuyback = buyBackAmount[_pool];
        require(config.boughtBackAmount < config.totalBuyBackAmount, "Total buyback amount reached");
        require(block.timestamp >= config.nextbuyBackTime, "Buyback not ready yet");
        require(availableBuyback > 0, "No Fund available for buyback");

        // Determine amount to use for this buyback
        uint256 amountToUse = availableBuyback >= config.AmountPerBuyBack 
            ? config.AmountPerBuyBack 
            : availableBuyback;
            
        // Create swap path
        address[] memory path = new address[](2);
        path[0] = config.tokenBAddress;
        path[1] = config.tokenAddress;
        
        // Execute swap
if (config.isNative) {
    // Use ETH as input
    IPancakeRouter(config.routerAddress).swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountToUse}(
        0, path, address(this), block.timestamp + 300
    );
} else {
    // Use token (e.g., USDT) as input
    IERC20(config.tokenBAddress).approve(config.routerAddress, amountToUse);
    IPancakeRouter(config.routerAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
        amountToUse, 0, path, address(this), block.timestamp + 300
    );
}
        // Get token balance
        address token = config.tokenAddress;
        uint256 tokenAmount = IBurnableToken(token).balanceOf(address(this));
        require(tokenAmount > 0, "No tokens to burn");
        
        // Try to burn tokens or send to dead address if burn function fails
        try IBurnableToken(token).burn(tokenAmount) {
            // Burn successful
        } catch {
            // Fallback: send to dead address
            IBurnableToken(token).transfer(0x000000000000000000000000000000000000dEaD, tokenAmount);
        }
        
        // Update state
        config.boughtBackAmount = config.boughtBackAmount.add(amountToUse);
        config.lastbuyBackTime = block.timestamp;
        
        // Calculate next buyback time
        if (availableBuyback > amountToUse) {
            // If we still have ETH, schedule next buyback
            config.nextbuyBackTime = block.timestamp.add(config.minBuyBackDeley);
        } else {
            // If no more ETH, set nextbuyBackTime to 0 to indicate no more buybacks
            config.nextbuyBackTime = 0;
        }   

        // Update remaining buyback amount
        buyBackAmount[_pool] = availableBuyback.sub(amountToUse);
        
        emit BuybackAndBurn(_pool, token, tokenAmount);
    }

    function checkUserAllow(address _pool ,address _user) internal view returns (bool){
        address Owner=OwnableUpgradeable(_pool).owner();
        bool rs;
        if(_user==Owner){
            rs=true;
        }else{
        rs= (_user!=Owner)&&(block.timestamp>poolConfig[_pool].lastbuyBackTime.add(poolConfig[_pool].maxBuyBackDeley))? true:false;      
        }
        return rs;
    }


  function demo()public  pure returns(string memory){
    return "Ekoo";
  }
    
    // Allow receiving ETH
    receive() external payable {}
  
}