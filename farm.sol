// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "@openzeppelin/contracts/utils/Address.sol";
import "./SafeControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./SafeMath.sol";
import "./MyERC20.sol";
contract Farm is Context,SafeControl,Ownable {
    using SafeMath for uint256;
    address private minter;//管理员
    address private myERC20Addr=0x315201d6B5bE13C6764c39Ea106D827396F0D651;//MBT address
    MyERC20 private myerc20=MyERC20(myERC20Addr);
    mapping(address => uint256) private _amounts;//账户--发放MBT数量
    uint256 private aproveunlocked=1;//领取锁，防止重放攻击
    bool private adminOperatelocked=false;//管理员进行 算力写入和donate时加锁，防止此时领取
    constructor() {
        minter=_msgSender();//合约创建者为管理员
    }
    /*...
    函数名：transferMintership  
    转移本合约管理员 为 addr
    */
    function transferMintership(address addr) public lock returns (bool) {
        require(Address.isContract(_msgSender())==false&&addr!=address(0),"CA");
        require(_msgSender()==minter,"not admin");
        minter=addr;
        return true;
    }
    /*...
    函数名：mint  
    给本合约也就是Farm合约发送指定_amount数量的MBT
    */
    function mint(uint256 _amount) public lock adminOperatelock returns (bool) {
        require(Address.isContract(_msgSender())==false&&_amount>0,"CA");
        require(_msgSender()==minter,"not admin");
        myerc20.mint(address(this),_amount);
        return true;
    }
     /*...
    函数名：adminSetAmounts  
    单个写入 _to 地址写入本周可领取的_toamount数量的MBT
    */
     function adminSetAmounts(address _to, uint256 _toamount) public lock adminOperatelock returns (bool) {
        require(Address.isContract(_msgSender())==false&&_to!=address(0)&&_toamount>0,"CA");
        require(_msgSender()==minter,"not admin");
        _amounts[_to]=_toamount;
        return true;
    }
     /*...
    函数名：adminSetAmountsBatch  
    批量写入 tos 中每个地址 对应 写入本周可领取的_toamounts对应数量的MBT
    _tos.length 必须与 _toamounts.length 相等
    */
    function adminSetAmountsBatch(address[] memory _tos, uint256[] memory _toamounts) public lock adminOperatelock returns (bool) {
        require(Address.isContract(_msgSender())==false,"CA");
        require(_msgSender()==minter,"not admin");
        uint count=_toamounts.length;
        for(uint i=0;i<count;i++){
            _amounts[_tos[i]]=_toamounts[i];
        }
        return true;
    }
    /*...
    函数名：balanceOf  
    单个查询 addr地址本周可领取MBT的数量
    返回值：可领取MBT的数量
    */
    function balanceOf(address addr) public view returns (uint256) {
        return _amounts[addr];
    }
    /*...
    函数名：balanceOfBatch  
    批量查询 addrs 中每个地址本周可领取的对应MBT的数量
    返回值：可领取MBT的数量的数组
    */
    function balanceOfBatch(address[] memory addrs) public view returns (uint256[] memory) {
        uint len=addrs.length;
        uint256[] memory res=new uint256[](len);
        for(uint i=0;i<len;i++){
            res[i]=_amounts[addrs[i]];
        }
        return res;
    }
    /*...
    函数名：reap  
    MBT领取 函数调用者msg.sender 中可领取的MBT,领取后msg.sender账户可领取MBT归零
    */
    function reap() public approvelock returns (bool) {
        require(Address.isContract(_msgSender())==false&&_msgSender()!=address(0),"CA");
        require(_amounts[_msgSender()]>0,"your amount < 0");
        require(adminOperatelocked==false,"admin Operate locked");
        uint am=balanceOf(_msgSender());
        _amounts[_msgSender()]=0;
        myerc20.transfer(_msgSender(),am);//MBT转移至用户账户
        return true;
    }
     /*...
    函数名：donate  
    Farm 合约MBT余额全部转移至 VIP 
    */
    function donate() public lock adminOperatelock returns (bool) {
        require(Address.isContract(_msgSender())==false,"CA");
        require(_msgSender()==minter,"not admin");
        uint256 contractMBTAmount=myerc20.balanceOf(address(this));//合约账户全部MBT余额
        myerc20.transfer(address(myERC20Addr),contractMBTAmount);//MBT转移至MBT合约账户
        return true;
    }
    //approve 锁，防止重放攻击
     modifier approvelock(){
        require(aproveunlocked==1,"LOCKED");
        aproveunlocked=0;
        _;
        aproveunlocked=1;
    }
    //管理员操作 锁
     modifier adminOperatelock(){
        require(adminOperatelocked==false,"Operate LOCKED");
        adminOperatelocked=true;
        _;
        adminOperatelocked=false;
    }
}
