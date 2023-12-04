contract ArbFlokiCeo is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    bool private swapping;

    DividendTracker public dividendTracker;

    address public MarketingWallet;

    uint256 public maxTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    //uint256 public liquidityActiveBlock = 0; // 0 means liquidity is not active yet
    //uint256 public tradingActiveBlock = 0; // 0 means trading is not active
    //uint256 public earlyBuyPenaltyEnd; // determines when snipers/bots can sell without extra penalty

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;

    // Anti-bot and anti-whale mappings and variables
    //mapping(address => uint256) private _holderLastTransferTimestamp; // to hold last Transfers temporarily during launch
    //bool public transferDelayEnabled = true;

    uint256 public constant feeDivisor = 100;

    uint256 public totalSellFees;
    uint256 public rewardsSellFee;
    uint256 public MarketingSellFee;
    uint256 public liquiditySellFee;

    uint256 public totalBuyFees;
    uint256 public rewardsBuyFee;
    uint256 public MarketingBuyFee;
    uint256 public liquidityBuyFee;

    uint256 public tokensForRewards;
    uint256 public tokensForMarketing;
    uint256 public tokensForLiquidity;

    uint256 public gasForProcessing = 0;

    uint256 public lpWithdrawRequestTimestamp;
    uint256 public lpWithdrawRequestDuration = 3 days;
    bool public lpWithdrawRequestPending;
    uint256 public lpPercToWithDraw;

    /******************/

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;

    mapping(address => bool) public _isExcludedMaxTransactionAmount;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event ExcludedMaxTransactionAmount(
        address indexed account,
        bool isExcluded
    );

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event MarketingWalletUpdated(
        address indexed newWallet,
        address indexed oldWallet
    );

    event DevWalletUpdated(
        address indexed newWallet,
        address indexed oldWallet
    );

    event GasForProcessingUpdated(
        uint256 indexed newValue,
        uint256 indexed oldValue
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(uint256 tokensSwapped, uint256 amount);

    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    event RequestedLPWithdraw();

    event WithdrewLPForMigration();

    event CanceledLpWithdrawRequest();

    constructor() ERC20("ARB FLOKI CEO", "AFC") {
        uint256 totalSupply = 100 * 1e7 * 1e18;

        maxTransactionAmount = (totalSupply * 2) / 100; // 2% maxTransactionAmountTxn
        swapTokensAtAmount = (totalSupply * 5) / 10000; // 0.05% swap tokens amount
        maxWallet = (totalSupply * 3) / 100; // 2% Max wallet

        rewardsBuyFee = 3;
        MarketingBuyFee = 32;
        liquidityBuyFee = 0;
        totalBuyFees = rewardsBuyFee + MarketingBuyFee + liquidityBuyFee;

        rewardsSellFee = 3;
        MarketingSellFee = 32;
        liquiditySellFee = 0;
        totalSellFees = rewardsSellFee + MarketingSellFee + liquiditySellFee;

        dividendTracker = new DividendTracker();

        MarketingWallet = address(msg.sender); // set as Marketing wallet

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        ); // sushiswap router on arbitrum - 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506

        // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));
        dividendTracker.excludeFromDividends(address(0xdead));

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(dividendTracker), true);
        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        excludeFromMaxTransaction(address(0xdead), true);

        _createInitialSupply(address(owner()), totalSupply);
    }

    receive() external payable {}

    // only use if conducting a presale
    function addPresaleAddressForExclusions(
        address _presaleAddress
    ) external onlyOwner {
        excludeFromFees(_presaleAddress, true);
        dividendTracker.excludeFromDividends(_presaleAddress);
        excludeFromMaxTransaction(_presaleAddress, true);
    }

    /*
     // disable Transfer delay - cannot be reenabled
    function disableTransferDelay() external onlyOwner returns (bool){
        transferDelayEnabled = false;
        return true;
    }

*/
    // excludes wallets and contracts from dividends (such as CEX hotwallets, etc.)
    function excludeFromDividends(address account) external onlyOwner {
        dividendTracker.excludeFromDividends(account);
    }

    // removes exclusion on wallets and contracts from dividends (such as CEX hotwallets, etc.)
    function includeInDividends(address account) external onlyOwner {
        dividendTracker.includeInDividends(account);
    }

    // once enabled, can never be turned off
    function enableTrading() external onlyOwner {
        require(!tradingActive, "Cannot re-enable trading");
        tradingActive = true;
        swapEnabled = true;
        //tradingActiveBlock = block.number;
    }

    // only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    function updateMaxAmount(uint256 newNum) external onlyOwner {
        require(
            newNum > ((totalSupply() * 1) / 1000) / 1e18,
            "Cannot set maxTransactionAmount lower than 0.1%"
        );
        maxTransactionAmount = newNum * (10 ** 18);
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(
            newNum > ((totalSupply() * 1) / 100) / 1e18,
            "Cannot set maxWallet lower than 1%"
        );
        maxWallet = newNum * (10 ** 18);
    }

    function updateBuyFees(
        uint256 _MarketingFee,
        uint256 _rewardsFee,
        uint256 _liquidityFee
    ) external onlyOwner {
        MarketingBuyFee = _MarketingFee;
        rewardsBuyFee = _rewardsFee;
        liquidityBuyFee = _liquidityFee;
        totalBuyFees = MarketingBuyFee + rewardsBuyFee + liquidityBuyFee;
        require(totalBuyFees <= 80, "Must keep fees at 80% or less");
    }

    function updateSellFees(
        uint256 _MarketingFee,
        uint256 _rewardsFee,
        uint256 _liquidityFee
    ) external onlyOwner {
        MarketingSellFee = _MarketingFee;
        rewardsSellFee = _rewardsFee;
        liquiditySellFee = _liquidityFee;
        totalSellFees = MarketingSellFee + rewardsSellFee + liquiditySellFee;
        require(totalSellFees <= 80, "Must keep fees at 80% or less");
    }

    function excludeFromMaxTransaction(
        address updAds,
        bool isEx
    ) public onlyOwner {
        _isExcludedMaxTransactionAmount[updAds] = isEx;
        emit ExcludedMaxTransactionAmount(updAds, isEx);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(
        address[] calldata accounts,
        bool excluded
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) external onlyOwner {
        require(
            pair != uniswapV2Pair,
            "The SushiSwap pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        excludeFromMaxTransaction(pair, value);

        if (value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateMarketingWallet(
        address newMarketingWallet
    ) external onlyOwner {
        require(newMarketingWallet != address(0), "may not set to 0 address");
        excludeFromFees(newMarketingWallet, true);
        emit MarketingWalletUpdated(newMarketingWallet, MarketingWallet);
        MarketingWallet = newMarketingWallet;
    }

    function updateGasForProcessing(uint256 newValue) external onlyOwner {
        require(
            newValue >= 200000 && newValue <= 500000,
            " gasForProcessing must be between 200,000 and 500,000"
        );
        require(
            newValue != gasForProcessing,
            "Cannot update gasForProcessing to same value"
        );
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns (uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed(
        address rewardToken
    ) external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed(rewardToken);
    }

    function isExcludedFromFees(address account) external view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(
        address account,
        address rewardToken
    ) external view returns (uint256) {
        return dividendTracker.withdrawableDividendOf(account, rewardToken);
    }

    function dividendTokenBalanceOf(
        address account
    ) external view returns (uint256) {
        return dividendTracker.holderBalance(account);
    }

    function getAccountDividendsInfo(
        address account,
        address rewardToken
    )
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccount(account, rewardToken);
    }

    function getAccountDividendsInfoAtIndex(
        uint256 index,
        address rewardToken
    )
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccountAtIndex(index, rewardToken);
    }

    function processDividendTracker(uint256 gas) external {
        (
            uint256 iterations,
            uint256 claims,
            uint256 lastProcessedIndex
        ) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(
            iterations,
            claims,
            lastProcessedIndex,
            false,
            gas,
            tx.origin
        );
    }

    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function getNumberOfDividends() external view returns (uint256) {
        return dividendTracker.totalBalance();
    }

    // remove limits after token is stable
    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        //transferDelayEnabled = false;
        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (!tradingActive) {
            require(
                _isExcludedFromFees[from] || _isExcludedFromFees[to],
                "Trading is not active yet."
            );
        }

        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !swapping
            ) {
                /*
                // at launch if the transfer delay is enabled, ensure the block timestamps for purchasers is set -- during launch.  
                if (transferDelayEnabled){
                    if (to != address(uniswapV2Router) && to != address(uniswapV2Pair)){
                        require(_holderLastTransferTimestamp[tx.origin] < block.number, "_transfer:: Transfer Delay enabled.  Only one purchase per block allowed.");
                        _holderLastTransferTimestamp[tx.origin] = block.number;
                    }
                }
                */

                //when buy
                if (
                    automatedMarketMakerPairs[from] &&
                    !_isExcludedMaxTransactionAmount[to]
                ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Buy transfer amount exceeds the maxTransactionAmount."
                    );
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Unable to exceed Max Wallet"
                    );
                }
                //when sell
                else if (
                    automatedMarketMakerPairs[to] &&
                    !_isExcludedMaxTransactionAmount[from]
                ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Sell transfer amount exceeds the maxTransactionAmount."
                    );
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Unable to exceed Max Wallet"
                    );
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;
            swapBack();
            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;

        // no taxes on transfers (non buys/sells)
        if (takeFee) {
            /*
            if(tradingActiveBlock + 1 >= block.number && (automatedMarketMakerPairs[to] || automatedMarketMakerPairs[from])){
                fees = amount.mul(99).div(100);
                tokensForLiquidity += fees * 33 / 99;
                tokensForRewards += fees * 33 / 99;
                tokensForMarketing += fees * 33 / 99;
            }
            */

            // on sell
            if (automatedMarketMakerPairs[to] && totalSellFees > 0) {
                fees = amount.mul(totalSellFees).div(feeDivisor);
                tokensForRewards += (fees * rewardsSellFee) / totalSellFees;
                tokensForLiquidity += (fees * liquiditySellFee) / totalSellFees;
                tokensForMarketing += (fees * MarketingSellFee) / totalSellFees;
            }
            // on buy
            else if (automatedMarketMakerPairs[from] && totalBuyFees > 0) {
                fees = amount.mul(totalBuyFees).div(feeDivisor);
                tokensForRewards += (fees * rewardsBuyFee) / totalBuyFees;
                tokensForLiquidity += (fees * liquidityBuyFee) / totalBuyFees;
                tokensForMarketing += (fees * MarketingBuyFee) / totalBuyFees;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);

        dividendTracker.setBalance(payable(from), balanceOf(from));
        dividendTracker.setBalance(payable(to), balanceOf(to));

        if (!swapping && gasForProcessing > 0) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (
                uint256 iterations,
                uint256 claims,
                uint256 lastProcessedIndex
            ) {
                emit ProcessedDividendTracker(
                    iterations,
                    claims,
                    lastProcessedIndex,
                    true,
                    gas,
                    tx.origin
                );
            } catch {}
        }
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0xdead),
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForLiquidity +
            tokensForMarketing +
            tokensForRewards;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }

        // Halve the amount of liquidity tokens
        uint256 liquidityTokens = (contractBalance * tokensForLiquidity) /
            totalTokensToSwap /
            2;
        uint256 amountToSwapForETH = contractBalance.sub(liquidityTokens);

        uint256 initialETHBalance = address(this).balance;

        swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance.sub(initialETHBalance);

        uint256 ethForMarketing = ethBalance.mul(tokensForMarketing).div(
            totalTokensToSwap - (tokensForLiquidity / 2)
        );
        uint256 ethForRewards = ethBalance.mul(tokensForRewards).div(
            totalTokensToSwap - (tokensForLiquidity / 2)
        );

        uint256 ethForLiquidity = ethBalance - ethForMarketing - ethForRewards;

        tokensForLiquidity = 0;
        tokensForMarketing = 0;
        tokensForRewards = 0;

        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            addLiquidity(liquidityTokens, ethForLiquidity);
            emit SwapAndLiquify(
                amountToSwapForETH,
                ethForLiquidity,
                tokensForLiquidity
            );
        }

        // call twice to force buy of both reward tokens.
        (bool success, ) = address(dividendTracker).call{value: ethForRewards}(
            ""
        );

        (success, ) = address(MarketingWallet).call{
            value: address(this).balance
        }("");
    }

    function withdrawStuckEth() external onlyOwner {
        (bool success, ) = address(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "failed to withdraw");
    }

    function requestToWithdrawLP(uint256 percToWithdraw) external onlyOwner {
        require(
            !lpWithdrawRequestPending,
            "Cannot request again until first request is over."
        );
        require(
            percToWithdraw <= 100 && percToWithdraw > 0,
            "Need to set between 1-100%"
        );
        lpWithdrawRequestTimestamp = block.timestamp;
        lpWithdrawRequestPending = true;
        lpPercToWithDraw = percToWithdraw;
        emit RequestedLPWithdraw();
    }

    function nextAvailableLpWithdrawDate() public view returns (uint256) {
        if (lpWithdrawRequestPending) {
            return lpWithdrawRequestTimestamp + lpWithdrawRequestDuration;
        } else {
            return 0; // 0 means no open requests
        }
    }

    function withdrawRequestedLP() external onlyOwner {
        require(
            block.timestamp >= nextAvailableLpWithdrawDate() &&
                nextAvailableLpWithdrawDate() > 0,
            "Must request and wait."
        );
        lpWithdrawRequestTimestamp = 0;
        lpWithdrawRequestPending = false;

        uint256 amtToWithdraw = (IERC20(address(uniswapV2Pair)).balanceOf(
            address(this)
        ) * lpPercToWithDraw) / 100;

        lpPercToWithDraw = 0;

        IERC20(uniswapV2Pair).transfer(msg.sender, amtToWithdraw);
    }

    function cancelLPWithdrawRequest() external onlyOwner {
        lpWithdrawRequestPending = false;
        lpPercToWithDraw = 0;
        lpWithdrawRequestTimestamp = 0;
        emit CanceledLpWithdrawRequest();
    }
}
