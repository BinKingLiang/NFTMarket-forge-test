// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/NFTMarket.sol";

contract MockERC721 is IERC721 {
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    
    function ownerOf(uint256 tokenId) public view override returns (address) {
        return _owners[tokenId];
    }
    
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory
    ) public override {
        _transfer(from, to, tokenId);
    }
    
    function _transfer(address from, address to, uint256 tokenId) internal {
        _owners[tokenId] = to;
        // 只有当 from 不是零地址时才减少余额
        if (from != address(0)) {
            _balances[from]--;
        }
        _balances[to]++;
    }
    
    // 实现其他必需的接口函数
    function balanceOf(address owner) external view override returns (uint256) {
        return _balances[owner];
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        _transfer(from, to, tokenId);
    }
    
    function transferFrom(address from, address to, uint256 tokenId) external override {
        _transfer(from, to, tokenId);
    }
    
    function approve(address to, uint256 tokenId) external override {}
    
    function getApproved(uint256 tokenId) external view override returns (address) {
        return address(0);
    }
    
    function setApprovalForAll(address operator, bool approved) external override {}
    
    function isApprovedForAll(address owner, address operator) external view override returns (bool) {
        return false;
    }
    
    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IERC721).interfaceId;
    }
}

contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    // 添加一个函数来设置余额
    function mint(address account, uint256 amount) external {
        balanceOf[account] = amount;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) 
        external override returns (bool) 
    {
        require(balanceOf[sender] >= amount, "ERC20: transfer amount exceeds balance");
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
    
    // 实现其他必需的接口函数
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "ERC20: transfer amount exceeds balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
    
    function totalSupply() external view override returns (uint256) {
        return 0;
    }
    
    function decimals() external view returns (uint8) {
        return 18;
    }
    
    function symbol() external view returns (string memory) {
        return "MOCK";
    }
    
    function name() external view returns (string memory) {
        return "Mock Token";
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract NFTMarketTest is Test {
    NFTMarket market;
    MockERC721 nft;
    MockERC20 token;
    address admin = address(1);
    address user1 = address(2);
    address user2 = address(3);
    
    // 导入事件
    event Listed(
        IERC721 indexed nft,
        uint256 indexed tokenId,
        address seller,
        uint256 price,
        IERC20 paymentToken
    );
    
    event Purchased(
        IERC721 indexed nft,
        uint256 indexed tokenId,
        address buyer,
        address seller,
        uint256 price,
        IERC20 paymentToken
    );

    function setUp() public {
        market = new NFTMarket();
        nft = new MockERC721();
        token = new MockERC20();
    }

    // 上架测试
    function testListing() public {
        // 成功上架
        vm.prank(admin);
        nft.safeTransferFrom(address(0), admin, 1);
        
        vm.expectEmit(true, true, true, true);
        emit Listed(nft, 1, admin, 1e18, token);
        
        vm.prank(admin);
        market.list(nft, 1, 1e18, token);
        
        // 非所有者上架失败
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NFTMarket.NotNFTOwner.selector));
        market.list(nft, 1, 1e18, token);
    }

    // 购买测试
    function testPurchase() public {
        // 准备上架
        vm.prank(admin);
        nft.safeTransferFrom(address(0), admin, 1);
        vm.prank(admin);
        market.list(nft, 1, 1e18, token);

        // 成功购买
        token.mint(user1, 1e18);
        vm.expectEmit(true, true, true, true);
        emit Purchased(nft, 1, user1, admin, 1e18, token);
        
        vm.prank(user1);
        market.purchase(nft, 1);

        // 重复购买失败
        vm.expectRevert(abi.encodeWithSelector(NFTMarket.NotForSale.selector));
        market.purchase(nft, 1);
    }

    // 边缘情况测试
    function testEdgeCases() public {
        // 准备上架
        vm.prank(admin);
        nft.safeTransferFrom(address(0), admin, 1);
        vm.prank(admin);
        market.list(nft, 1, 1e18, token);

        // 自己购买自己
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(NFTMarket.SelfPurchase.selector));
        market.purchase(nft, 1);

        // 支付不足
        token.mint(user1, 0.9e18);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NFTMarket.InsufficientPayment.selector));
        market.purchase(nft, 1);
    }

    // 模糊测试
    function testFuzzy(uint96 rawPrice, address buyer) public {
        uint256 price = bound(rawPrice, 0.01e18, 10000e18);
        vm.assume(buyer != address(0) && buyer != admin);

        // 上架NFT
        vm.prank(admin);
        nft.safeTransferFrom(address(0), admin, 1);
        vm.prank(admin);
        market.list(nft, 1, price, token);

        // 设置买家余额
        deal(address(token), buyer, price);
        
        // 执行购买
        vm.prank(buyer);
        market.purchase(nft, 1);

        // 验证NFT转移
        assertEq(nft.ownerOf(1), buyer);
    }

    // 不可变测试
    function testInvariant() public {
        // 执行正常交易
        testPurchase();
        
        // 验证市场合约无代币持仓
        assertEq(token.balanceOf(address(market)), 0);
        
        // 验证无残留上架记录
        (address seller,,) = market.listings(nft, 1);
        assertEq(seller, address(0));
    }
}
