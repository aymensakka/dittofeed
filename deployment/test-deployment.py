#!/usr/bin/env python3
"""
Test Dittofeed deployment endpoints
"""
import os
import sys
import time
import json
import requests
from urllib.parse import urlparse

# Configuration from environment
API_URL = os.getenv('API_URL', 'https://api.com.caramelme.com')
DASHBOARD_URL = os.getenv('DASHBOARD_URL', 'https://dashboard.com.caramelme.com')
AUTH_MODE = os.getenv('AUTH_MODE', 'multi-tenant')

# Colors for output
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'

def print_header(title):
    """Print a formatted header"""
    print(f"\n{BLUE}{'='*50}{RESET}")
    print(f"{BLUE}{title}{RESET}")
    print(f"{BLUE}{'='*50}{RESET}")

def test_endpoint(url, name, expected_status=200, timeout=10):
    """Test a single endpoint"""
    try:
        print(f"Testing {name}: {url}")
        response = requests.get(url, timeout=timeout, allow_redirects=True)
        
        if response.status_code == expected_status:
            print(f"  {GREEN}✅ Success (HTTP {response.status_code}){RESET}")
            return True
        elif response.status_code in [200, 301, 302, 304]:
            print(f"  {GREEN}✅ OK (HTTP {response.status_code}){RESET}")
            return True
        else:
            print(f"  {RED}❌ Failed (HTTP {response.status_code}){RESET}")
            return False
            
    except requests.exceptions.ConnectionError:
        print(f"  {RED}❌ Connection failed{RESET}")
        return False
    except requests.exceptions.Timeout:
        print(f"  {RED}❌ Timeout after {timeout}s{RESET}")
        return False
    except Exception as e:
        print(f"  {RED}❌ Error: {str(e)}{RESET}")
        return False

def test_api_health():
    """Test API health endpoint"""
    url = f"{API_URL}/health"
    try:
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            data = response.json()
            print(f"  {GREEN}✅ API Health: {json.dumps(data, indent=2)}{RESET}")
            return True
    except:
        pass
    return test_endpoint(url, "API Health")

def test_dashboard():
    """Test dashboard availability"""
    return test_endpoint(DASHBOARD_URL, "Dashboard", expected_status=200)

def test_api_root():
    """Test API root endpoint"""
    return test_endpoint(API_URL, "API Root")

def main():
    """Run all tests"""
    print_header("🚀 Dittofeed Deployment Test")
    
    print(f"\nConfiguration:")
    print(f"  API URL: {API_URL}")
    print(f"  Dashboard URL: {DASHBOARD_URL}")
    print(f"  Auth Mode: {AUTH_MODE}")
    
    # Track results
    results = []
    
    print_header("1. External Endpoint Tests")
    
    # Test each endpoint
    results.append(("API Health", test_api_health()))
    results.append(("API Root", test_api_root()))
    results.append(("Dashboard", test_dashboard()))
    
    # Test workspace endpoints if multi-tenant
    if AUTH_MODE == 'multi-tenant':
        print_header("2. Multi-Tenant Endpoints")
        results.append(("Workspaces", test_endpoint(f"{API_URL}/api/workspaces", "Workspaces API")))
    
    # Summary
    print_header("📊 Test Summary")
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    print(f"\nResults:")
    for name, result in results:
        status = f"{GREEN}✅ PASS{RESET}" if result else f"{RED}❌ FAIL{RESET}"
        print(f"  {name}: {status}")
    
    print(f"\n{BLUE}Total: {passed}/{total} tests passed{RESET}")
    
    if passed == total:
        print(f"\n{GREEN}🎉 All tests passed! Deployment is operational.{RESET}")
        print(f"\nAccess your Dittofeed instance:")
        print(f"  Dashboard: {DASHBOARD_URL}")
        print(f"  API: {API_URL}")
        return 0
    else:
        print(f"\n{YELLOW}⚠️  Some tests failed. Check the logs above.{RESET}")
        print(f"\nTroubleshooting:")
        print(f"  1. Verify Cloudflare tunnel is connected")
        print(f"  2. Check if all services are running in Coolify")
        print(f"  3. Ensure DATABASE_URL is properly formatted")
        print(f"  4. Verify PostgreSQL database 'dittofeed' exists")
        return 1

if __name__ == "__main__":
    sys.exit(main())