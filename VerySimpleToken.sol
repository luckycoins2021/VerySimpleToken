// SPDX-License-Identifier: Unlicensed
/*
#VerySimpleToken - 5% auto LP, 2% dev tax -> 7% total tax
                 - LP will be burn at lunch 
                 - owner will be renounce al lunch
                 - no mint function
                 - no chance to rake back ownership 
                 - no dev wallets who can dump tokens
                 - fair lunch
                 - contract use trusted source interfaces (OpenZeppelin & Uniswap) direct from github
                 - the code is simple and easy to read
                 - all initial tokens will be added in lP, no burn to hide wallets size, 21.000.000 token supply
*/
pragma solidity ^0.8.5;
// imports:
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract VerySimpleToken is Context, IERC20, Ownable {
   using SafeMath for uint256;
   using Address for address;
   
    mapping (address => uint256) private balance;
    mapping (address => mapping (address => uint256)) private allowances;
    mapping (address => bool) private isExcludedFromFee; //for contract owner, and router
 // token info
    uint256 private tSupply = 21000000  * 10 ** 9; 
    uint8 private maxTxAmountProcent=20;
    uint256 private maxTxAmount = tSupply.mul(maxTxAmountProcent).div(100); //20% from supply, maximum tx amount
    address payable private bnbAdress;
    string private _name = "VerySimpleToken";
    string private _symbol = "VST";
    uint8 private _decimals = 9;
//swap bools
    bool private inSwapAndLiquify;
    bool private swapAndLiquifyEnabled=true;
// fees
    uint256 private liquidityFee = 5;//5% from transaction
    uint256 private devFee = 2;//2% from transaction
//pair addres
    address private uniswapV2Pair;
    IUniswapV2Router02 private uniswapV2Router;
// events
    event Received(address sender, uint amount);
    event LPaddedAutomated(uint tokenAmmount, uint ethAmount);
    event SwapAndTranfer(uint tokensForDev, uint ethAmountToTransfer);
    event SwapTokenForETH(uint256 tokenAmount, uint256 ethAmount);
//lp 
    uint256 private lpAdded=0;
    uint256 private tokenLpAdded=0;
    uint256 private ethLpAdded=0;
// min values for swap and lpAdded
    uint256 private minAmountForLPAndDev = 10000 * 10 **_decimals; // in wei
    
    
    constructor (address payable _router, address payable _bnbAdress) public {
        bnbAdress=_bnbAdress;
        balance[owner()] = tSupply;
        //uni router and pair
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router=_uniswapV2Router;
        //exclude owner, uniswappair and this contract from fee
        isExcludedFromFee[owner()] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[_bnbAdress] = true;
        isExcludedFromFee[address(uniswapV2Pair)] = true;
        emit Transfer(address(0), owner(), tSupply);
    }
    function name() public view returns (string memory) {
        return _name;
    }
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    function decimals() public view returns (uint8) {
        return _decimals;
    }
    function setMaxTxProcent(uint8 _mtp) public onlyOwner {
        maxTxAmountProcent= _mtp;
    }
    function getMaxTxProcent() public view returns (uint256) {
        return maxTxAmountProcent;
    }
    function getMaxTxAmount() public view returns (uint256) {
        return maxTxAmount;
    }
    function totalSupply() public view override returns (uint256) {
        return tSupply;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return balance[account];
    }
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _Transfer(msg.sender, recipient, amount);
        return true;
    }
    function allowance(address owner, address spender) public view override returns (uint256) {
        return allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _Transfer(sender, recipient, amount);
        _approve(sender, msg.sender, allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, allowances[msg.sender][spender].add(addedValue));
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }
    function isAdressExcludedFromFee(address account) public view returns(bool) {
        return isExcludedFromFee[account];
    }
    function totalFees() public view returns (uint256) {
        return liquidityFee+devFee;
    }
    function excludeFromFee(address account) external onlyOwner {
        isExcludedFromFee[account] = true;
    }
    function includeInFee(address account) external onlyOwner {
        isExcludedFromFee[account] = false;
    }
    function setLiquidityFeePercent(uint256 _liquidityFee) external onlyOwner {
        liquidityFee = _liquidityFee;
    }
    function setDevFeePrecent(uint256 _devFee) external onlyOwner {
        devFee = _devFee;
    }
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
    function getAmountOfTokensAddToLP() public view returns (uint256) {
        return tokenLpAdded;
    }
    function getAmountOfETHAddToLP() public view returns (uint256) {
        return ethLpAdded;
    }
    function _takeFee(address sender,uint256 amount) private {
        balance[address(this)]=balance[address(this)].add(amount);
        balance[sender]=balance[sender].sub(amount);
        emit Transfer(msg.sender, address(this), amount);
    }
   function calculateFee(uint256 amount) private view returns (uint256) {
        return amount.mul(totalFees()).div(10**2);
    }
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
   modifier lockTheSwap { //for add lp
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    //this method is responsible for taking all fee, if takeFee is true
    function _Transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(balance[sender]>=amount, "inssuficient balance");
        
        if(sender != owner() && recipient != owner())
            require(amount <= maxTxAmount, "Transfer amount exceeds the maxTxAmount."); 
           
        uint256 finalTransferAmount= amount;
        if (!inSwapAndLiquify)
            if (!isExcludedFromFee[sender] || !isExcludedFromFee[recipient]){
                finalTransferAmount = finalTransferAmount.sub(calculateFee(finalTransferAmount));
                _takeFee(sender,amount.sub(finalTransferAmount));
            }
        
        if (!inSwapAndLiquify && sender != uniswapV2Pair && swapAndLiquifyEnabled) {
            checkAddLPSwapTransfer(); 
        }
       
        _tokenTransfer(sender,recipient,finalTransferAmount);
        }
        
        function _tokenTransfer(address sender, address recipient, uint256 amount) private {
            balance[sender] = balance[sender].sub(amount);
            balance[recipient] = balance[recipient].add(amount);
            emit Transfer(sender, recipient, amount);
        }
    
    function swapExactTokenForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
        emit SwapTokenForETH(tokenAmount,0);
    }
    
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        (uint256 _amountTokenAdded, uint256 _amountETHAdded, uint256 _liquidityAdded) = 
                                            uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
        tokenLpAdded=tokenLpAdded.add(_amountTokenAdded);
        ethLpAdded=ethLpAdded.add(_amountETHAdded);
        lpAdded=lpAdded.add(_liquidityAdded);
        emit LPaddedAutomated(tokenAmount,ethAmount);
    } 
    
    function checkAddLPSwapTransfer () private lockTheSwap{ //this function manage the dev fee and LP
        if(balance[address(this)]>=minAmountForLPAndDev){
               
                uint256 initialTokenBallance = balance[address(this)];
                if(initialTokenBallance>maxTxAmount)
                    initialTokenBallance=maxTxAmount;
                uint256 tokensForDev = initialTokenBallance.mul(devFee.mul(100).div(totalFees())).div(100);
                swapExactTokenForETH(tokensForDev);
                uint256 ethAmountToTransfer=address(this).balance;
                bnbAdress.transfer(address(this).balance);
                emit SwapAndTranfer(tokensForDev,ethAmountToTransfer);
                
                initialTokenBallance = balance[address(this)];
                if(initialTokenBallance>maxTxAmount)
                    initialTokenBallance=maxTxAmount;
                uint256 tokensForLP = initialTokenBallance;
                uint256 halfForSwap = tokensForLP.div(2);
                uint256 estimatedEthAmount=address(this).balance;
                swapExactTokenForETH(halfForSwap);
                estimatedEthAmount=address(this).balance.sub(estimatedEthAmount);
                addLiquidity(tokensForLP.sub(halfForSwap),estimatedEthAmount);
                emit LPaddedAutomated(halfForSwap,estimatedEthAmount);
            }
    }
}