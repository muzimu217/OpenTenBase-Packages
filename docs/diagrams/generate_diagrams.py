#!/usr/bin/env python3
"""
生成 OpenTenBase 教学文档图表
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches

# 设置中文字体
plt.rcParams['font.sans-serif'] = ['Arial Unicode MS', 'SimHei']
plt.rcParams['axes.unicode_minus'] = False


def generate_architecture():
    """生成架构图"""
    fig, ax = plt.subplots(1, 1, figsize=(12, 8))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 10)
    ax.axis('off')

    # 标题
    ax.text(6, 9.5, 'OpenTenBase 分布式架构', ha='center', va='top', 
            fontsize=16, weight='bold')

    # GTM
    gtm = patches.FancyBboxPatch((4, 7), 4, 1.5, boxstyle="round,pad=0.2", 
                                  fc='#E6F3FF', ec='#2196F3', linewidth=2)
    ax.add_patch(gtm)
    ax.text(6, 7.75, 'GTM\n(Global Transaction Manager)\nPort: 6666', 
            ha='center', va='center', fontsize=10, weight='bold')

    # Coordinator
    coord = patches.FancyBboxPatch((0.5, 4), 4, 1.5, boxstyle="round,pad=0.2", 
                                    fc='#E8F5E9', ec='#4CAF50', linewidth=2)
    ax.add_patch(coord)
    ax.text(2.5, 4.75, 'Coordinator\n(协调节点)\nPort: 5432', 
            ha='center', va='center', fontsize=10, weight='bold')

    # Datanode 1
    dn1 = patches.FancyBboxPatch((7.5, 4), 4, 1.5, boxstyle="round,pad=0.2", 
                                  fc='#FFF9E6', ec='#FF9800', linewidth=2)
    ax.add_patch(dn1)
    ax.text(9.5, 4.75, 'Datanode 1\n(数据节点)\nPort: 15432', 
            ha='center', va='center', fontsize=10, weight='bold')

    # Datanode 2
    dn2 = patches.FancyBboxPatch((0.5, 1), 4, 1.5, boxstyle="round,pad=0.2", 
                                  fc='#FFF9E6', ec='#FF9800', linewidth=2)
    ax.add_patch(dn2)
    ax.text(2.5, 1.75, 'Datanode 2\n(数据节点)\nPort: 15433', 
            ha='center', va='center', fontsize=10, weight='bold')

    # Datanode 3
    dn3 = patches.FancyBboxPatch((7.5, 1), 4, 1.5, boxstyle="round,pad=0.2", 
                                  fc='#FFF9E6', ec='#FF9800', linewidth=2)
    ax.add_patch(dn3)
    ax.text(9.5, 1.75, 'Datanode 3\n(数据节点)\nPort: 15434', 
            ha='center', va='center', fontsize=10, weight='bold')

    # Connections (arrows)
    # GTM -> Coordinator
    ax.arrow(5.5, 7, -1, 2, head_width=0.2, fc='#2196F3', ec='#2196F3', linewidth=2)
    ax.arrow(6.5, 7, 1, 2, head_width=0.2, fc='#2196F3', ec='#2196F3', linewidth=2)
    ax.text(6, 6.2, '事务协调', ha='center', fontsize=8, color='#2196F3')

    # Coordinator -> Datanode 1
    ax.arrow(4.5, 4, 2.8, 0, head_width=0.2, fc='#4CAF50', ec='#4CAF50', linewidth=2)
    ax.text(6.5, 3.7, '路由 SQL', ha='center', fontsize=8, color='#4CAF50')

    # Datanode 1 -> Datanode 2/3
    ax.arrow(9.5, 4, -5.8, 1.5, head_width=0.2, fc='#FF9800', ec='#FF9800', 
             linewidth=2, linestyle='--')
    ax.arrow(9.5, 4, 0, -1.5, head_width=0.2, fc='#FF9800', ec='#FF9800', 
             linewidth=2, linestyle='--')
    ax.text(10.5, 3.2, '数据同步', ha='left', fontsize=8, color='#FF9800')

    # 添加图例
    legend_elements = [
        patches.Patch(facecolor='#E6F3FF', edgecolor='#2196F3', label='GTM - 全局事务管理'),
        patches.Patch(facecolor='#E8F5E9', edgecolor='#4CAF50', label='Coordinator - SQL 协调'),
        patches.Patch(facecolor='#FFF9E6', edgecolor='#FF9800', label='Datanode - 数据存储'),
    ]
    ax.legend(handles=legend_elements, loc='upper right', fontsize=8)

    plt.tight_layout()
    plt.savefig('architecture.png', dpi=150, bbox_inches='tight')
    print("✓ architecture.png 已生成")


def generate_query_flow():
    """生成查询流程图"""
    fig, ax = plt.subplots(1, 1, figsize=(10, 12))
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 12)
    ax.axis('off')

    # 标题
    ax.text(5, 11.5, '分布式查询流程', ha='center', va='top', 
            fontsize=16, weight='bold')

    # Client
    client = patches.FancyBboxPatch((3, 10), 4, 1, boxstyle="round,pad=0.2", 
                                     fc='#FFEBEE', ec='#F44336', linewidth=2)
    ax.add_patch(client)
    ax.text(5, 10.5, 'Client\n(客户端)', ha='center', va='center', fontsize=10, weight='bold')

    # Coordinator
    coord = patches.FancyBboxPatch((3, 7.5), 4, 1.5, boxstyle="round,pad=0.2", 
                                    fc='#E8F5E9', ec='#4CAF50', linewidth=2)
    ax.add_patch(coord)
    ax.text(5, 8.25, 'Coordinator\n(协调节点)', ha='center', va='center', fontsize=10, weight='bold')

    # pgxc_node
    pgxc = patches.FancyBboxPatch((3, 5.5), 4, 1, boxstyle="round,pad=0.2", 
                                   fc='#E3F2FD', ec='#2196F3', linewidth=2)
    ax.add_patch(pgxc)
    ax.text(5, 6, 'pgxc_node 表\n(节点信息)', ha='center', va='center', fontsize=9, weight='bold')

    # GTM
    gtm = patches.FancyBboxPatch((3, 3.5), 4, 1, boxstyle="round,pad=0.2", 
                                  fc='#F3E5F5', ec='#9C27B0', linewidth=2)
    ax.add_patch(gtm)
    ax.text(5, 4, 'GTM\n(全局事务)', ha='center', va='center', fontsize=10, weight='bold')

    # Datanode 1
    dn1 = patches.FancyBboxPatch((1, 1), 3, 1, boxstyle="round,pad=0.2", 
                                  fc='#FFF9E6', ec='#FF9800', linewidth=2)
    ax.add_patch(dn1)
    ax.text(2.5, 1.5, 'DN001', ha='center', va='center', fontsize=10, weight='bold')

    # Datanode 2
    dn2 = patches.FancyBboxPatch((6, 1), 3, 1, boxstyle="round,pad=0.2", 
                                  fc='#FFF9E6', ec='#FF9800', linewidth=2)
    ax.add_patch(dn2)
    ax.text(7.5, 1.5, 'DN002', ha='center', va='center', fontsize=10, weight='bold')

    # Flow arrows with labels
    # Client -> Coordinator
    ax.arrow(5, 10, 0, -1.3, head_width=0.15, fc='black', ec='black', linewidth=2)
    ax.text(5.3, 9.3, '① SQL', ha='left', fontsize=8, fontweight='bold')

    # Coordinator -> pgxc_node
    ax.arrow(5, 7.5, 0, -0.8, head_width=0.15, fc='black', ec='black', linewidth=2)
    ax.text(5.3, 6.7, '② 查询', ha='left', fontsize=8)

    # Coordinator -> GTM
    ax.arrow(5, 7.5, 0, -2.8, head_width=0.15, fc='black', ec='black', linewidth=2)
    ax.text(5.3, 5.2, '③ 申请 GXID', ha='left', fontsize=8)

    # Coordinator -> Datanodes
    ax.arrow(4.5, 7.5, -1.5, -5.3, head_width=0.15, fc='#4CAF50', ec='#4CAF50', linewidth=2)
    ax.arrow(5.5, 7.5, 1.5, -5.3, head_width=0.15, fc='#4CAF50', ec='#4CAF50', linewidth=2)
    ax.text(5.8, 4, '④ 路由 SQL', ha='left', fontsize=8, color='#4CAF50')

    # Return paths (dashed)
    ax.arrow(2.5, 1, 0.8, 6.3, head_width=0.15, fc='gray', ec='gray', 
             linewidth=2, linestyle='--')
    ax.arrow(7.5, 1, -0.8, 6.3, head_width=0.15, fc='gray', ec='gray', 
             linewidth=2, linestyle='--')
    ax.text(3.3, 4.5, '⑤ 返回结果', ha='left', fontsize=8)

    # Coordinator -> Client (final)
    ax.arrow(5, 7.5, 0, 1.3, head_width=0.15, fc='#F44336', ec='#F44336', linewidth=2)
    ax.text(5.3, 8.8, '⑥ 聚合结果', ha='left', fontsize=8, color='#F44336', fontweight='bold')

    plt.tight_layout()
    plt.savefig('query-flow.png', dpi=150, bbox_inches='tight')
    print("✓ query-flow.png 已生成")


if __name__ == '__main__':
    print("开始生成图表...")
    generate_architecture()
    generate_query_flow()
    print("\n所有图表生成完成！")