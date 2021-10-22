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
    address private myERC20Addr=0xeca182999fe00D41e229e4061CA40954B8EaE5ED;//MBT address
    MyERC20 private myerc20=MyERC20(myERC20Addr);
    uint256 private aproveunlocked=1;//领取锁，防止重放攻击
    bool private adminOperatelocked=false;//管理员进行 算力写入和donate时加锁，防止此时领取


    mapping( uint256=>uint256) public totalAllocPoint;//总的算力
    mapping(uint256 => mapping(address => uint256)) private allocPoint;//周期--账户--算力
    uint256 public pice=0;//周期
    uint256 public lastRewardBlock;//上次结算时区块
    uint256 public rewardTokenPerBlock;//每个区块的奖励


    constructor(uint256 _rewardTokenPerBlock) {
        minter=_msgSender();//合约创建者为管理员
        rewardTokenPerBlock = _rewardTokenPerBlock;//定义每个区块的token奖励
        lastRewardBlock = block.number;
        
    }
   /*...
    函数名：update  
    更新用户算力，更新总算力，并结算捐赠 ，置零累计领取，更新上次结算时区块。
    */
    function setupdate(address[] memory _tos, uint256[] memory _computPower,uint _rewardTokenPerBlock,uint _pice)  public adminOperatelock returns(bool) {
        require(Address.isContract(_msgSender())==false,"CA");
        require(_msgSender()==minter,"not admin");
        //更新每个区块的奖励
        rewardTokenPerBlock=_rewardTokenPerBlock;
        pice=_pice;//更新周期 
        //更新算力
        uint count=_tos.length;
        for(uint i=0;i<count;i++){
            totalAllocPoint[pice]=totalAllocPoint[pice].add(_computPower[i]);//更新 累加总算力
            allocPoint[pice][_tos[i]]=_computPower[i];//更新算力
        }
        uint256 lessToken=getRewardTokenBlockReward();
        lastRewardBlock =  block.number;//新的区块起点
        myerc20.mint(address(this),lessToken);//mint剩余区块的累计奖励 到合约
        //账户合约全部余额捐赠
        uint256 donateToken= myerc20.balanceOf(address(this));
        myerc20.transfer(address(myERC20Addr),donateToken);//MBT转移至MBT合约账户  捐赠
            
        
        return true;
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
    函数名：computationalPowerOf 
    单个查询 addr地址本周  算力
    返回值：可领取MBT的数量
    */
    function computationalPowerOf(address addr) public view returns (uint256) {
        return allocPoint[pice][addr];
    }
    /*...
    函数名：computationalPowerOfBatch
    批量查询 addrs 中每个地址本周  算力
    返回值：可领取MBT的数量的数组
    */
    function computationalPowerOfBatch(address[] memory addrs) public view returns (uint256[] memory) {
        uint len=addrs.length;
        uint256[] memory res=new uint256[](len);
        for(uint i=0;i<len;i++){
            res[i]=allocPoint[pice][addrs[i]];
        }
        return res;
    }
    //计算区块总奖励
    function getRewardTokenBlockReward() public view returns (uint256) {
        if(lastRewardBlock>=block.number){
             return 0;
        }
       return block.number.sub(lastRewardBlock).mul(rewardTokenPerBlock);//当前区块-上次更新时的区快数   x    每个区块的奖励 = 区块数总奖励
    }

    /*...
    函数名：reap  
    MBT领取 函数调用者msg.sender 更具 算力与经历的区块数量 计算收益,领取后msg.sender账户算力 归零
    */
    function reap() public approvelock returns (bool) {
        require(Address.isContract(_msgSender())==false,"CA");
        require(adminOperatelocked==false,"admin Operate locked");
        if(allocPoint[pice][_msgSender()]<=0){//算力0返回
            return false;
        }
        if (block.number <= lastRewardBlock) {//领取收益当时的blockNumber > 上一次领取时的blockNumber
            return false;
        }
        uint256 blockReward = getRewardTokenBlockReward();//计算从上次更新算力后的 累计区块 奖励
        if (blockReward <= 0) {
            return false;
        }
        uint256 tokenReward = blockReward.mul(allocPoint[pice][_msgSender()]).div(totalAllocPoint[pice]);//更具  user算力与总算力的占比 计算自己能获得的token
        totalAllocPoint[pice]=totalAllocPoint[pice].sub(allocPoint[pice][_msgSender()]);//总算力减少
        allocPoint[pice][_msgSender()]=0;//用户算力归零  下次更新算力前不能再收获了

        lastRewardBlock=block.number;


        require(myerc20.mint(address(this),blockReward), "mint error");//mint总的区块的奖励 到合约
        myerc20.transfer(_msgSender(),tokenReward);//MBT转移 user能够获得的 至用户账户
        return true;
    }
    
    /*...
    函数名：reapView  
    MBT领取预查看 函数调用者msg.sender 更具 算力与经历的区块数量 计算收益
    */
    function reapView(address addr) public view returns (uint256) {
        require(adminOperatelocked==false&&addr!=address(0),"admin Operate locked  and not address0");
        if(allocPoint[pice][addr]<=0)//算力必须大于0
        {
            return 0;
        }
        if (block.number <= lastRewardBlock) {//领取收益当时的blockNumber > 上一次领取时的blockNumber
            return 0;
        }
        uint256 blockReward = getRewardTokenBlockReward();//计算从上次更新算力后的 累计区块 奖励
        if (blockReward <= 0) {
            return 0;
        }
        uint256 tokenReward = blockReward.mul(allocPoint[pice][addr]).div(totalAllocPoint[pice]);//更具  user算力与总算力的占比 计算自己能获得的token
        return tokenReward;
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
