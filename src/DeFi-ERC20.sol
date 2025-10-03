// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IERC20 {
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
    function balanceOf(address _owner) external view returns (uint256 balance);
    function transfer(address _to, uint256 _value) external returns (bool success);
}

contract DeFi {
    bool private _locked;

    modifier noReentrant() {
        require(!_locked, "No reentrancy allowed");
        _locked = true;
        _;
        _locked = false;
    }

    struct LoanStatus {
        uint borrowedAmount;
        address tokenAddress;
        bool isActive;
    }

    mapping(address => LoanStatus) public userLoans;
    mapping(address => mapping(address => uint)) public tokenDepositBalances;

    event LoanCreated(address indexed user, address token, uint amount);
    event LoanRepaid(address indexed user, address token, uint amount);
    event DepositCreated(address indexed user, address token, uint amount);

    function borrow(address _tokenAddress, uint256 _borrowAmount) external noReentrant() {
        require(_borrowAmount > 0, "Borrow amount must be greater than 0");
        require(userLoans[msg.sender].isActive == false, "You already have an active loan");
        
        uint vaultTokenBalance = IERC20(_tokenAddress).balanceOf(address(this));
        require(vaultTokenBalance >= _borrowAmount, "Contract has insufficient tokens to lend");

        userLoans[msg.sender] = LoanStatus({
            borrowedAmount: _borrowAmount,
            tokenAddress: _tokenAddress,
            isActive: true
        });

        bool success = IERC20(_tokenAddress).transfer(msg.sender, _borrowAmount);
        require(success, "Loan transfer failed");

        emit LoanCreated(msg.sender, _tokenAddress, _borrowAmount);
    }

    function repayLoan(uint _amount, address _tokenAddress) external noReentrant() {
        LoanStatus storage loan = userLoans[msg.sender];
        require(loan.isActive == true, "You don't have an active loan");

        uint principalAmount = loan.borrowedAmount;
        require(_amount >= principalAmount, "Repayment amount is insufficient");

        bool success = IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
        require(success, "Repayment transfer failed");

        loan.borrowedAmount = 0;
        loan.isActive = false;

        emit LoanRepaid(msg.sender, _tokenAddress, _amount);
    }

    function deposit(address _tokenAddress, uint _amount) external {
        require(_amount > 0, "Deposit amount must be greater than zero");

        bool success = IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
        require(success, "Deposit failed, check your allowance");

        tokenDepositBalances[msg.sender][_tokenAddress] += _amount;

        emit DepositCreated(msg.sender, _tokenAddress, _amount);
    }

    function withdraw(address _tokenAddress, uint _amount) external noReentrant {
        require(_amount > 0, "Withdrawal amount must be greater than zero");
        require(tokenDepositBalances[msg.sender][_tokenAddress] >= _amount, "Insufficient balance for withdrawal");

        tokenDepositBalances[msg.sender][_tokenAddress] -= _amount;

        bool success = IERC20(_tokenAddress).transfer(msg.sender, _amount);
        require(success, "Withdrawal failed");
    }

    function getDepositBalance(address _tokenAddress) external view returns (uint) {
        return tokenDepositBalances[msg.sender][_tokenAddress];
    }

    function getTotalDeposits(address _tokenAddress) external view returns (uint) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }
}