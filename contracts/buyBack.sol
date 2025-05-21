// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./SafeMath.sol";

interface IPancakeRouter {
    function WETH() external pure returns (address);
    
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
}

interface IBurnableToken {
    function burn(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract BuyBackManager is Initializable, OwnableUpgradeable , ReentrancyGuardUpgradeable {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;    

    struct BuyBackConfig {
     address tokenAddress;
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
    }
    
    uint256 public amountPerBuyBack;
    uint256 public minBuyBackDeley;
    uint256 public maxBuyBackDeley;

    mapping(address => BuyBackConfig) public poolConfig;
    mapping(address => uint256) public buyBackAmount;
    mapping(address => bool) public isAllowed;

    // Events
    event BuybackAndBurn(address indexed pool, address indexed token, uint256 amount);
    event PoolConfigured(address indexed pool, address indexed token, uint8 percentage);
    event PoolFinalized(address indexed pool, uint256 amount);
    event PermissionUpdated(address indexed user, bool allowed);

   function initialize(uint256 _amountPerBuyBack, uint256 _minBuyBackDeley, uint256 _maxBuyBackDeley) public initializer {
                __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        amountPerBuyBack = _amountPerBuyBack;
        minBuyBackDeley = _minBuyBackDeley;
        maxBuyBackDeley = _maxBuyBackDeley;
    }
    
    // Function to set permissions for pool owners/factory
    function setAllowed(address _user, bool _allowed) external  {
        isAllowed[_user] = _allowed;
        emit PermissionUpdated(_user, _allowed);
    }

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
            address _tokenAddress,
            address _routerAddress,
            uint8 _percentage,
            uint256 _totalBuyBackAmount
        ) external  {
            require(_pool != address(0), "Invalid pool address");
            require(_tokenAddress != address(0), "Invalid token address");
            require(_percentage > 0 && _percentage <= 100, "Percentage must be between 1-100");
            require(_totalBuyBackAmount > 0, "Total buyback amount must be > 0");
            
            poolConfig[_pool] = BuyBackConfig({
                tokenAddress: _tokenAddress,
                routerAddress: _routerAddress,
                percentage: _percentage,
                totalBuyBackAmount:_totalBuyBackAmount,
                boughtBackAmount: 0,
                AmountPerBuyBack: amountPerBuyBack,
                minBuyBackDeley: minBuyBackDeley,
                maxBuyBackDeley: maxBuyBackDeley,
                nextbuyBackTime: 0, // Will be set during finalization
                lastbuyBackTime: 0,  // Will be set during finalization
                isConfigured: false
            });
        
            emit PoolConfigured(_pool, _tokenAddress, _percentage);
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

    function finalizeBuyBackConfig(address _pool) external payable  {
        require(_pool != address(0), "Invalid pool address");
        require(!poolConfig[_pool].isConfigured, "Pool already configured");
        require(poolConfig[_pool].totalBuyBackAmount > 0, "Total buyback amount must be > 0");
        require(msg.value > 0, "Must send ETH for buybacks");
        
        buyBackAmount[_pool] = msg.value;
        
        BuyBackConfig storage config = poolConfig[_pool];
        config.isConfigured = true;
        config.totalBuyBackAmount=msg.value;
        config.nextbuyBackTime = block.timestamp.add(config.minBuyBackDeley);
        config.lastbuyBackTime = block.timestamp;
        
        emit PoolFinalized(_pool, msg.value);
    }
    
    function buybackAndBurn(address _pool) nonReentrant onlyAuthorized(_pool,msg.sender) external  {
        BuyBackConfig storage config = poolConfig[_pool];
        uint256 availableBuyback = buyBackAmount[_pool];
        require(config.boughtBackAmount < config.totalBuyBackAmount, "Total buyback amount reached");
        require(block.timestamp >= config.nextbuyBackTime, "Buyback not ready yet");
        require(availableBuyback > 0, "No ETH available for buyback");

        // Determine amount to use for this buyback
        uint256 amountToUse = availableBuyback >= config.AmountPerBuyBack 
            ? config.AmountPerBuyBack 
            : availableBuyback;
            
        // Create swap path
        address[] memory path = new address[](2);
        path[0] = IPancakeRouter(config.routerAddress).WETH();
        path[1] = config.tokenAddress;
        
        // Execute swap
        IPancakeRouter(config.routerAddress).swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountToUse}(
            0, // Accept any amount (no slippage protection)
            path,
            address(this),
            block.timestamp + 300 // 5 minutes deadline
        );
        
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
        config.boughtBackAmount = config.boughtBackAmount.add(tokenAmount);
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
    
    
    // Allow receiving ETH
    receive() external payable {}
}