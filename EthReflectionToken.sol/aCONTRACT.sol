// SPDX-License-Identifier: No License

/*
comment from token creator...[EMPTY]

--------------------

Want to create similar token?
Ask all your questions and join our community - https://t.me/team_solidity
Or write to our E-mail - web3@rimer.finance
Token generated with ❤️ on web3.rid.team
                           _                     _                  _
  ___ _ __ ___   __ _ _ __| |_    ___ ___  _ __ | |_ _ __ __ _  ___| |_
 / __| '_ ` _ \ / _` | '__| __|  / __/ _ \| '_ \| __| '__/ _` |/ __| __|
 \__ \ | | | | | (_| | |  | |_  | (_| (_) | | | | |_| | | (_| | (__| |_
 |___/_| |_| |_|\__,_|_|   \__|  \___\___/|_| |_|\__|_|  \__,_|\___|\__|
*/

pragma solidity ^0.8.19;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable2Step.sol";
import "./CoinDividendTracker.sol";

import "./Initializable.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router01.sol";
import "./IUniswapV2Router02.sol";

contract EthReflectionToken is ERC20, ERC20Burnable, Ownable2Step, DividendTrackerFunctions, Initializable {
    
    uint16 public swapThresholdRatio;
    
    uint256 private _mwPending;
    uint256 private _liquidityPending;
    uint256 private _rewardsPending;

    address public mwAddress;
    uint16[3] public mwFees;

    uint16[3] public autoBurnFees;

    uint16[3] public liquidityFees;

    uint16[3] public rewardsFees;

    mapping (address => bool) public isExcludedFromFees;

    uint16[3] public totalFees;
    bool private _swapping;

    IUniswapV2Router02 public routerV2;
    address public pairV2;
    mapping (address => bool) public AMMPairs;

    mapping (address => bool) public isExcludedFromLimits;

    uint256 public maxWalletAmount;

    uint256 public maxBuyAmount;
    uint256 public maxSellAmount;
    uint256 public maxTransferAmount;

    bool public tradingEnabled;
    mapping (address => bool) public isExcludedFromTradingRestriction;
 
    event SwapThresholdUpdated(uint16 swapThresholdRatio);

    event mwAddressUpdated(address mwAddress);
    event mwFeesUpdated(uint16 buyFee, uint16 sellFee, uint16 transferFee);
    event mwFeeSent(address recipient, uint256 amount);

    event autoBurnFeesUpdated(uint16 buyFee, uint16 sellFee, uint16 transferFee);
    event autoBurned(uint256 amount);

    event liquidityFeesUpdated(uint16 buyFee, uint16 sellFee, uint16 transferFee);
    event liquidityAdded(uint amountToken, uint amountCoin, uint liquidity);
    event ForceLiquidityAdded(uint256 leftoverTokens, uint256 unaddedTokens);

    event rewardsFeesUpdated(uint16 buyFee, uint16 sellFee, uint16 transferFee);
    event rewardsFeeSent(uint256 amount);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event RouterV2Updated(address indexed routerV2);
    event AMMPairsUpdated(address indexed AMMPair, bool isPair);

    event ExcludeFromLimits(address indexed account, bool isExcluded);

    event MaxWalletAmountUpdated(uint256 maxWalletAmount);

    event MaxBuyAmountUpdated(uint256 maxBuyAmount);
    event MaxSellAmountUpdated(uint256 maxSellAmount);
    event MaxTransferAmountUpdated(uint256 maxTransferAmount);

    event TradingEnabled();
    event ExcludeFromTradingRestriction(address indexed account, bool isExcluded);
 
    constructor()
        ERC20(unicode"Eth Reflection Token", unicode"REFLECT") 
    {
        address supplyRecipient = 0x494f450F13060c0215B54f4C37b6F88d14264c38;
        
        updateSwapThreshold(50);

        mwAddressSetup(0x494f450F13060c0215B54f4C37b6F88d14264c38);
        mwFeesSetup(800, 800, 800);

        autoBurnFeesSetup(0, 0, 0);

        liquidityFeesSetup(100, 100, 100);

        _deployDividendTracker(600, 10000 * (10 ** decimals()) / 10);

        gasForProcessingSetup(300000);
        rewardsFeesSetup(100, 100, 100);
        _excludeFromDividends(supplyRecipient, true);
        _excludeFromDividends(address(this), true);
        _excludeFromDividends(address(0), true);
        _excludeFromDividends(address(dividendTracker), true);

        excludeFromFees(supplyRecipient, true);
        excludeFromFees(address(this), true); 

        _excludeFromLimits(supplyRecipient, true);
        _excludeFromLimits(address(this), true);
        _excludeFromLimits(address(0), true); 

        updateMaxWalletAmount(1000000 * (10 ** decimals()) / 10);

        updateMaxBuyAmount(100000 * (10 ** decimals()) / 10);
        updateMaxSellAmount(100000 * (10 ** decimals()) / 10);
        updateMaxTransferAmount(100000 * (10 ** decimals()) / 10);

        excludeFromTradingRestriction(supplyRecipient, true);
        excludeFromTradingRestriction(address(this), true);

        _mint(supplyRecipient, 10000000 * (10 ** decimals()) / 10);
        _transferOwnership(0x494f450F13060c0215B54f4C37b6F88d14264c38);
    }
    
    /*
        This token is not upgradeable, but uses both the constructor and initializer for post-deployment setup.
    */
    function initialize(address _router) initializer external {
        _updateRouterV2(_router);
    }

    receive() external payable {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    function _swapTokensForCoin(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = routerV2.WETH();

        _approve(address(this), address(routerV2), tokenAmount);

        routerV2.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function updateSwapThreshold(uint16 _swapThresholdRatio) public onlyOwner {
        require(_swapThresholdRatio > 0 && _swapThresholdRatio <= 500, "SwapThreshold: Cannot exceed limits from 0.01% to 5% for new swap threshold");
        swapThresholdRatio = _swapThresholdRatio;
        
        emit SwapThresholdUpdated(_swapThresholdRatio);
    }

    function getSwapThresholdAmount() public view returns (uint256) {
        return balanceOf(pairV2) * swapThresholdRatio / 10000;
    }

    function getAllPending() public view returns (uint256) {
        return 0 + _mwPending + _liquidityPending + _rewardsPending;
    }

    function mwAddressSetup(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "TaxesDefaultRouterWallet: Wallet tax recipient cannot be a 0x0 address");

        mwAddress = _newAddress;
        excludeFromFees(_newAddress, true);
        _excludeFromLimits(_newAddress, true);

        emit mwAddressUpdated(_newAddress);
    }

    function mwFeesSetup(uint16 _buyFee, uint16 _sellFee, uint16 _transferFee) public onlyOwner {
        totalFees[0] = totalFees[0] - mwFees[0] + _buyFee;
        totalFees[1] = totalFees[1] - mwFees[1] + _sellFee;
        totalFees[2] = totalFees[2] - mwFees[2] + _transferFee;
        require(totalFees[0] <= 2500 && totalFees[1] <= 2500 && totalFees[2] <= 2500, "TaxesDefaultRouter: Cannot exceed max total fee of 25%");

        mwFees = [_buyFee, _sellFee, _transferFee];

        emit mwFeesUpdated(_buyFee, _sellFee, _transferFee);
    }

    function autoBurnFeesSetup(uint16 _buyFee, uint16 _sellFee, uint16 _transferFee) public onlyOwner {
        totalFees[0] = totalFees[0] - autoBurnFees[0] + _buyFee;
        totalFees[1] = totalFees[1] - autoBurnFees[1] + _sellFee;
        totalFees[2] = totalFees[2] - autoBurnFees[2] + _transferFee;
        require(totalFees[0] <= 2500 && totalFees[1] <= 2500 && totalFees[2] <= 2500, "TaxesDefaultRouter: Cannot exceed max total fee of 25%");

        autoBurnFees = [_buyFee, _sellFee, _transferFee];

        emit autoBurnFeesUpdated(_buyFee, _sellFee, _transferFee);
    }

    function _swapAndLiquify(uint256 tokenAmount) private returns (uint256 leftover) {
        // Sub-optimal method for supplying liquidity
        uint256 halfAmount = tokenAmount / 2;
        uint256 otherHalf = tokenAmount - halfAmount;

        _swapTokensForCoin(halfAmount);

        uint256 coinBalance = address(this).balance;

        if (coinBalance > 0) {
            (uint amountToken, uint amountCoin, uint liquidity) = _addLiquidity(otherHalf, coinBalance);

            emit liquidityAdded(amountToken, amountCoin, liquidity);

            return otherHalf - amountToken;
        } else {
            return otherHalf;
        }
    }

    function _addLiquidity(uint256 tokenAmount, uint256 coinAmount) private returns (uint, uint, uint) {
        _approve(address(this), address(routerV2), tokenAmount);

        return routerV2.addLiquidityETH{value: coinAmount}(address(this), tokenAmount, 0, 0, address(0), block.timestamp);
    }

    function addLiquidityFromLeftoverTokens() external {
        uint256 leftoverTokens = balanceOf(address(this)) - getAllPending();

        uint256 unaddedTokens = _swapAndLiquify(leftoverTokens);

        emit ForceLiquidityAdded(leftoverTokens, unaddedTokens);
    }

    function liquidityFeesSetup(uint16 _buyFee, uint16 _sellFee, uint16 _transferFee) public onlyOwner {
        totalFees[0] = totalFees[0] - liquidityFees[0] + _buyFee;
        totalFees[1] = totalFees[1] - liquidityFees[1] + _sellFee;
        totalFees[2] = totalFees[2] - liquidityFees[2] + _transferFee;
        require(totalFees[0] <= 2500 && totalFees[1] <= 2500 && totalFees[2] <= 2500, "TaxesDefaultRouter: Cannot exceed max total fee of 25%");

        liquidityFees = [_buyFee, _sellFee, _transferFee];

        emit liquidityFeesUpdated(_buyFee, _sellFee, _transferFee);
    }

    function _sendDividends(uint256 tokenAmount) private {
        _swapTokensForCoin(tokenAmount);

        uint256 dividends = address(this).balance;
        
        if (dividends > 0) {
            (bool success,) = payable(address(dividendTracker)).call{value: dividends}("");
            if (success) emit rewardsFeeSent(dividends);
        }
    }

    function excludeFromDividends(address account, bool isExcluded) external onlyOwner {
        _excludeFromDividends(account, isExcluded);
    }

    function _excludeFromDividends(address account, bool isExcluded) internal override {
        dividendTracker.excludeFromDividends(account, balanceOf(account), isExcluded);
    }

    function rewardsFeesSetup(uint16 _buyFee, uint16 _sellFee, uint16 _transferFee) public onlyOwner {
        totalFees[0] = totalFees[0] - rewardsFees[0] + _buyFee;
        totalFees[1] = totalFees[1] - rewardsFees[1] + _sellFee;
        totalFees[2] = totalFees[2] - rewardsFees[2] + _transferFee;
        require(totalFees[0] <= 2500 && totalFees[1] <= 2500 && totalFees[2] <= 2500, "TaxesDefaultRouter: Cannot exceed max total fee of 25%");

        rewardsFees = [_buyFee, _sellFee, _transferFee];

        emit rewardsFeesUpdated(_buyFee, _sellFee, _transferFee);
    }

    function _burn(address account, uint256 amount) internal override {
        super._burn(account, amount);
        
        dividendTracker.setBalance(account, balanceOf(account));
    }

    function _mint(address account, uint256 amount) internal override {
        super._mint(account, amount);
        
        dividendTracker.setBalance(account, balanceOf(account));
    }

    function excludeFromFees(address account, bool isExcluded) public onlyOwner {
        isExcludedFromFees[account] = isExcluded;
        
        emit ExcludeFromFees(account, isExcluded);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (!_swapping && amount > 0 && to != address(routerV2) && !isExcludedFromFees[from] && !isExcludedFromFees[to]) {
            uint256 fees = 0;
            uint8 txType = 3;
            
            if (AMMPairs[from]) {
                if (totalFees[0] > 0) txType = 0;
            }
            else if (AMMPairs[to]) {
                if (totalFees[1] > 0) txType = 1;
            }
            else if (totalFees[2] > 0) txType = 2;
            
            if (txType < 3) {
                
                uint256 autoBurnPortion = 0;

                fees = amount * totalFees[txType] / 10000;
                amount -= fees;
                
                _mwPending += fees * mwFees[txType] / totalFees[txType];

                if (autoBurnFees[txType] > 0) {
                    autoBurnPortion = fees * autoBurnFees[txType] / totalFees[txType];
                    _burn(from, autoBurnPortion);
                    emit autoBurned(autoBurnPortion);
                }

                _liquidityPending += fees * liquidityFees[txType] / totalFees[txType];

                _rewardsPending += fees * rewardsFees[txType] / totalFees[txType];

                fees = fees - autoBurnPortion;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }
        }
        
        bool canSwap = getAllPending() >= getSwapThresholdAmount() && balanceOf(pairV2) > 0;
        
        if (!_swapping && !AMMPairs[from] && from != address(routerV2) && canSwap) {
            _swapping = true;
            
            if (false || _mwPending > 0) {
                uint256 token2Swap = 0 + _mwPending;
                bool success = false;

                _swapTokensForCoin(token2Swap);
                uint256 coinsReceived = address(this).balance;
                
                uint256 mwPortion = coinsReceived * _mwPending / token2Swap;
                if (mwPortion > 0) {
                    success = payable(mwAddress).send(mwPortion);
                    if (success) {
                        emit mwFeeSent(mwAddress, mwPortion);
                    }
                }
                _mwPending = 0;

            }

            if (_liquidityPending > 0) {
                _swapAndLiquify(_liquidityPending);
                _liquidityPending = 0;
            }

            if (_rewardsPending > 0 && getNumberOfDividendTokenHolders() > 0) {
                _sendDividends(_rewardsPending);
                _rewardsPending = 0;
            }

            _swapping = false;
        }

        super._transfer(from, to, amount);
        
        dividendTracker.setBalance(from, balanceOf(from));
        dividendTracker.setBalance(to, balanceOf(to));
        
        if (!_swapping) try dividendTracker.process(gasForProcessing) {} catch {}

    }

    function _updateRouterV2(address router) private {
        routerV2 = IUniswapV2Router02(router);
        pairV2 = IUniswapV2Factory(routerV2.factory()).createPair(address(this), routerV2.WETH());
        
        _excludeFromDividends(router, true);

        _excludeFromLimits(router, true);

        _setAMMPair(pairV2, true);

        emit RouterV2Updated(router);
    }

    function setAMMPair(address pair, bool isPair) external onlyOwner {
        require(pair != pairV2, "DefaultRouter: Cannot remove initial pair from list");

        _setAMMPair(pair, isPair);
    }

    function _setAMMPair(address pair, bool isPair) private {
        AMMPairs[pair] = isPair;

        if (isPair) { 
            _excludeFromDividends(pair, true);

            _excludeFromLimits(pair, true);

        }

        emit AMMPairsUpdated(pair, isPair);
    }

    function excludeFromLimits(address account, bool isExcluded) external onlyOwner {
        _excludeFromLimits(account, isExcluded);
    }

    function _excludeFromLimits(address account, bool isExcluded) internal {
        isExcludedFromLimits[account] = isExcluded;

        emit ExcludeFromLimits(account, isExcluded);
    }

    function updateMaxWalletAmount(uint256 _maxWalletAmount) public onlyOwner {
        require(_maxWalletAmount >= _maxWalletSafeLimit(), "MaxWallet: Limit too low");
        maxWalletAmount = _maxWalletAmount;
        
        emit MaxWalletAmountUpdated(_maxWalletAmount);
    }

    function _maxWalletSafeLimit() private view returns (uint256) {
        return totalSupply() / 1000;
    }

    function _maxTxSafeLimit() private view returns (uint256) {
        return totalSupply() * 5 / 10000;
    }

    function updateMaxBuyAmount(uint256 _maxBuyAmount) public onlyOwner {
        require(_maxBuyAmount >= _maxTxSafeLimit(), "MaxTx: Limit too low");
        maxBuyAmount = _maxBuyAmount;
        
        emit MaxBuyAmountUpdated(_maxBuyAmount);
    }

    function updateMaxSellAmount(uint256 _maxSellAmount) public onlyOwner {
        require(_maxSellAmount >= _maxTxSafeLimit(), "MaxTx: Limit too low");
        maxSellAmount = _maxSellAmount;
        
        emit MaxSellAmountUpdated(_maxSellAmount);
    }

    function updateMaxTransferAmount(uint256 _maxTransferAmount) public onlyOwner {
        require(_maxTransferAmount >= _maxTxSafeLimit(), "MaxTx: Limit too low");
        maxTransferAmount = _maxTransferAmount;
        
        emit MaxTransferAmountUpdated(_maxTransferAmount);
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "EnableTrading: Trading was enabled already");
        tradingEnabled = true;
        
        emit TradingEnabled();
    }

    function excludeFromTradingRestriction(address account, bool isExcluded) public onlyOwner {
        isExcludedFromTradingRestriction[account] = isExcluded;
        
        emit ExcludeFromTradingRestriction(account, isExcluded);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        if (AMMPairs[from] && !isExcludedFromLimits[to]) { // BUY
            require(amount <= maxBuyAmount, "MaxTx: Cannot exceed max buy limit");
        }
    
        if (AMMPairs[to] && !isExcludedFromLimits[from]) { // SELL
            require(amount <= maxSellAmount, "MaxTx: Cannot exceed max sell limit");
        }
    
        if (!AMMPairs[to] && !isExcludedFromLimits[from]) { // OTHER
            require(amount <= maxTransferAmount, "MaxTx: Cannot exceed max transfer limit");
        }
    
        // Interactions with DEX are disallowed prior to enabling trading by owner
        if ((AMMPairs[from] && !isExcludedFromTradingRestriction[to]) || (AMMPairs[to] && !isExcludedFromTradingRestriction[from])) {
            require(tradingEnabled, "EnableTrading: Trading was not enabled yet");
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        if (!isExcludedFromLimits[to]) {
            require(balanceOf(to) <= maxWalletAmount, "MaxWallet: Cannot exceed max wallet limit");
        }

        super._afterTokenTransfer(from, to, amount);
    }
}