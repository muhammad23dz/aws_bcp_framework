#!/usr/bin/env python3
"""
Local unit test for lambda_function.py
Tests all report generation logic with fully mocked AWS services (no real AWS calls).
"""

import sys
import os
import json
import unittest
from unittest.mock import MagicMock, patch
from io import BytesIO

# Add parent dir to path so we can import lambda_function
sys.path.insert(0, '/Users/qawer7/.gemini/antigravity/scratch/aws_bcp_framework')

# ─── Sample Security Hub findings ────────────────────────────────────────────
SAMPLE_FINDINGS = [
    {
        "Id": "finding-001",
        "Title": "S3 bucket public access",
        "Description": "Bucket allows public access",
        "Severity": {"Label": "HIGH"},
        "Compliance": {"Status": "FAILED"},
        "WorkflowState": "NEW",
        "RecordState": "ACTIVE",
        "Resources": [{"Type": "AWS::S3::Bucket", "Id": "arn:aws:s3:::my-bucket"}],
        "CreatedAt": "2026-08-01T10:00:00Z",
        "UpdatedAt": "2026-08-01T10:00:00Z",
        "AwsAccountId": "417441750480",
        "Region": "us-east-1",
        "GeneratorId": "aws-foundational-security-best-practices/v/1.0.0/S3.2",
    },
    {
        "Id": "finding-002",
        "Title": "IAM root account MFA not enabled",
        "Description": "Root account should have MFA",
        "Severity": {"Label": "CRITICAL"},
        "Compliance": {"Status": "FAILED"},
        "WorkflowState": "NEW",
        "RecordState": "ACTIVE",
        "Resources": [{"Type": "AWS::IAM::Account", "Id": "arn:aws:iam::417441750480:root"}],
        "CreatedAt": "2026-08-01T11:00:00Z",
        "UpdatedAt": "2026-08-01T11:00:00Z",
        "AwsAccountId": "417441750480",
        "Region": "us-east-1",
        "GeneratorId": "aws-foundational-security-best-practices/v/1.0.0/IAM.9",
    },
    {
        "Id": "finding-003",
        "Title": "CloudTrail not enabled",
        "Description": "CloudTrail should be enabled in all regions",
        "Severity": {"Label": "MEDIUM"},
        "Compliance": {"Status": "FAILED"},
        "WorkflowState": "NEW",
        "RecordState": "ACTIVE",
        "Resources": [{"Type": "AWS::CloudTrail::Trail", "Id": "arn:aws:cloudtrail:::trail/test"}],
        "CreatedAt": "2026-08-01T12:00:00Z",
        "UpdatedAt": "2026-08-01T12:00:00Z",
        "AwsAccountId": "417441750480",
        "Region": "us-east-1",
        "GeneratorId": "aws-foundational-security-best-practices/v/1.0.0/CT.1",
    },
]


def build_mock_session():
    """Build a boto3.Session mock that returns mocked securityhub and s3 clients."""
    mock_securityhub = MagicMock()
    mock_s3 = MagicMock()

    # Mock describe_hub (non-fatal check)
    mock_securityhub.describe_hub.return_value = {
        "HubArn": "arn:aws:securityhub:us-east-1:417441750480:hub/default"
    }

    # Mock paginator to return sample findings
    mock_paginator = MagicMock()
    mock_paginator.paginate.return_value = [{"Findings": SAMPLE_FINDINGS}]
    mock_securityhub.get_paginator.return_value = mock_paginator

    # Mock S3 put_object
    mock_s3.put_object.return_value = {"ResponseMetadata": {"HTTPStatusCode": 200}}

    # Build session mock
    mock_session = MagicMock()
    mock_session.client.side_effect = lambda svc, **kw: (
        mock_securityhub if svc == 'securityhub' else mock_s3
    )

    return mock_session, mock_securityhub, mock_s3


class TestLambdaFunction(unittest.TestCase):

    @patch.dict(os.environ, {
        'S3_BUCKET_NAME': 'test-bcp-bucket',
        'AWS_DEFAULT_REGION': 'us-east-1',
    })
    def test_get_security_hub_findings(self):
        """Test that findings are retrieved and returned as a list"""
        _, mock_securityhub, _ = build_mock_session()
        from lambda_function import get_security_hub_findings
        findings = get_security_hub_findings(mock_securityhub)
        self.assertEqual(len(findings), 3)
        self.assertEqual(findings[0]['Id'], 'finding-001')
        print(f"  ✅ get_security_hub_findings: returned {len(findings)} findings")

    @patch.dict(os.environ, {
        'S3_BUCKET_NAME': 'test-bcp-bucket',
        'AWS_DEFAULT_REGION': 'us-east-1',
    })
    def test_transform_findings_data(self):
        """Test that findings are transformed into structured dicts"""
        from lambda_function import transform_findings_data
        transformed = transform_findings_data(SAMPLE_FINDINGS)
        self.assertEqual(len(transformed), 3)
        # Check required keys exist in transformed findings
        first = transformed[0]
        for key in ['Finding_ID', 'Title', 'Severity_Label', 'Compliance_Status', 'AWS_Account_ID', 'Region']:
            self.assertIn(key, first, f"Missing key '{key}' in transformed finding")
        print(f"  ✅ transform_findings_data: {len(transformed)} findings transformed correctly")

    @patch.dict(os.environ, {
        'S3_BUCKET_NAME': 'test-bcp-bucket',
        'AWS_DEFAULT_REGION': 'us-east-1',
    })
    def test_create_summary_statistics(self):
        """Test summary statistics generation"""
        from lambda_function import transform_findings_data, create_summary_statistics
        transformed = transform_findings_data(SAMPLE_FINDINGS)
        stats = create_summary_statistics(transformed)
        self.assertIn('severity_breakdown', stats)
        self.assertIn('compliance_breakdown', stats)
        print(f"  ✅ create_summary_statistics: {stats['severity_breakdown']}")

    @patch.dict(os.environ, {
        'S3_BUCKET_NAME': 'test-bcp-bucket',
        'AWS_DEFAULT_REGION': 'us-east-1',
    })
    def test_excel_report_generated(self):
        """Test that an Excel workbook is generated in-memory"""
        import openpyxl
        from lambda_function import (
            transform_findings_data, create_summary_statistics,
            create_summary_sheet, create_findings_sheet, create_pivot_sheet
        )
        transformed = transform_findings_data(SAMPLE_FINDINGS)
        stats = create_summary_statistics(transformed)
        wb = openpyxl.Workbook()
        create_summary_sheet(wb, stats, len(SAMPLE_FINDINGS))
        create_findings_sheet(wb, transformed)
        create_pivot_sheet(wb, transformed)
        # Save to buffer and verify it's a valid xlsx
        buf = BytesIO()
        wb.save(buf)
        content = buf.getvalue()
        self.assertTrue(content[:2] == b'PK', "Output is not a valid Excel file (expected PK magic bytes)")
        print(f"  ✅ Excel report generated: {len(content):,} bytes, valid xlsx format")

    @patch.dict(os.environ, {
        'S3_BUCKET_NAME': 'test-bcp-bucket',
        'AWS_DEFAULT_REGION': 'us-east-1',
    })
    @patch('boto3.Session')
    def test_lambda_handler_full(self, mock_session_cls):
        """Test the full lambda_handler flow end-to-end with mocked AWS"""
        mock_session, _, _ = build_mock_session()
        mock_session_cls.return_value = mock_session

        from lambda_function import lambda_handler
        result = lambda_handler({}, {})

        self.assertEqual(result['statusCode'], 200, f"Expected 200, got {result['statusCode']}. Body: {result['body']}")
        body = json.loads(result['body'])
        self.assertIn('key', body)
        self.assertIn('findings_count', body)
        self.assertEqual(body['findings_count'], 3)
        print(f"  ✅ lambda_handler: statusCode=200, findings_count={body['findings_count']}, key={body['key']}")

    def test_no_naive_datetime(self):
        """Verify no bare datetime.now() calls exist (all must be timezone-aware UTC)"""
        with open('/Users/qawer7/.gemini/antigravity/scratch/aws_bcp_framework/lambda_function.py') as f:
            source = f.read()
        bare_now = source.count('datetime.now()')
        self.assertEqual(bare_now, 0, f"Found {bare_now} bare datetime.now() call(s) — should use datetime.now(timezone.utc)")
        print("  ✅ datetime check: all datetime calls are timezone-aware (UTC)")

    def test_no_maxitems_cap(self):
        """Verify MaxItems cap has been removed from paginator config"""
        with open('/Users/qawer7/.gemini/antigravity/scratch/aws_bcp_framework/lambda_function.py') as f:
            source = f.read()
        self.assertNotIn("'MaxItems'", source, "Found MaxItems cap in paginator — should be removed to fetch all findings")
        print("  ✅ MaxItems check: no findings cap found (all pages will be retrieved)")


if __name__ == '__main__':
    print("\n══════════════════════════════════════════════════════")
    print("  AWS BCP Framework — Lambda Function Unit Test Suite")
    print("══════════════════════════════════════════════════════\n")
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestLambdaFunction)
    runner = unittest.TextTestRunner(verbosity=0)
    result = runner.run(suite)
    print("\n══════════════════════════════════════════════════════")
    if result.wasSuccessful():
        print(f"  RESULT: ✅ ALL {result.testsRun} TESTS PASSED")
    else:
        print(f"  RESULT: ❌ {len(result.failures)} FAILURE(S), {len(result.errors)} ERROR(S)")
    print("══════════════════════════════════════════════════════\n")
    sys.exit(0 if result.wasSuccessful() else 1)
